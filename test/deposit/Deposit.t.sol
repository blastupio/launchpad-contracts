// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {Deposit} from "../../src/Deposit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {RouterMock} from "../../src/mocks/RouterMock.sol";

contract DepositTest is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    struct SignatureData {
        address sender;
        uint256 projectId;
        address depositToken;
        uint256 amount;
        uint256 deadline;
        address depositReceiver;
        uint256 nonce;
        bytes data;
    }

    address internal admin;
    uint256 internal adminPrivateKey;
    address internal signer;
    uint256 internal signerPrivateKey;

    address user;
    address user2;
    address user3;
    address receiver;

    ERC20Mock depositToken;
    ERC20Mock otherToken;
    Deposit deposit;
    uint256 timeToDeadline;
    RouterMock router;

    function setUp() public virtual {
        adminPrivateKey = 0xa11ce;
        signerPrivateKey = 0xbcd12e;
        admin = vm.addr(adminPrivateKey);
        signer = vm.addr(signerPrivateKey);
        user = address(10);
        user2 = address(11);
        user3 = address(12);
        receiver = address(13);
        timeToDeadline = 120;

        vm.startPrank(admin);
        router = new RouterMock();
        depositToken = new ERC20Mock("Token", "TKN", 18);
        otherToken = new ERC20Mock("Other Token", "OTKN", 18);
        deposit = new Deposit(admin, signer, receiver);
        vm.stopPrank();
    }

    function _getSignature(SignatureData memory signatureData) internal returns (bytes memory signature) {
        vm.startPrank(signer);
        bytes32 digest = keccak256(
            abi.encodePacked(
                signatureData.sender,
                signatureData.projectId,
                signatureData.depositToken,
                signatureData.amount,
                signatureData.deadline,
                signatureData.depositReceiver,
                signatureData.nonce,
                signatureData.data
            )
        ).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
    }

    function test_deposit_invalidSignature() public {
        // check invalid deadline
        uint256 currentDeadline = block.timestamp + timeToDeadline;
        uint256 nonce = 0;
        bytes memory data = "Bytes";
        vm.warp(currentDeadline + 1);
        uint256 projectId = 1;
        uint256 amount = 10 * 1e18;
        SignatureData memory signatureData = SignatureData(
            user, projectId, address(depositToken), amount - 10, currentDeadline, deposit.depositReceiver(), nonce, data
        );
        bytes memory signature = _getSignature(signatureData);
        depositToken.mint(user, 1e30);
        vm.startPrank(user);
        depositToken.approve(address(deposit), type(uint256).max);
        // check pause/unpause
        vm.expectRevert();
        deposit.pause();
        vm.expectRevert();
        deposit.unpause();
        vm.stopPrank();
        vm.prank(admin);
        deposit.pause();

        vm.startPrank(user);
        vm.expectRevert();
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.stopPrank();

        vm.prank(admin);
        deposit.unpause();

        vm.startPrank(user);
        vm.expectRevert("BlastUP: the deadline for this signature has passed");
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.warp(block.timestamp - 60);
        vm.expectRevert();
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.stopPrank();
    }

    function test_deposit_invalidNonce() public {
        uint256 currentDeadline = block.timestamp + timeToDeadline;
        uint256 nonce = 0;
        bytes memory data = "Bytes";
        uint256 projectId = 1;
        uint256 amount = 10 * 1e18;
        SignatureData memory signatureData = SignatureData(
            user, projectId, address(depositToken), amount, currentDeadline, deposit.depositReceiver(), nonce, data
        );
        // check setSigner
        vm.prank(admin);
        deposit.setSigner(user2);
        bytes memory signature = _getSignature(signatureData);
        vm.startPrank(user);
        depositToken.mint(user, 1e30);
        depositToken.approve(address(deposit), type(uint256).max);
        vm.expectRevert("BlastUP: signature verification failed");
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.stopPrank();

        vm.prank(admin);
        deposit.setSigner(signer);
        signature = _getSignature(signatureData);
        // check nonce
        vm.startPrank(user);
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.expectRevert("BlastUP: this nonce is already used");
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.stopPrank();
    }

    function test_depositWithSwap_NotWhitelisted() public {
        uint256 currentDeadline = block.timestamp + timeToDeadline;
        uint256 nonce = 0;
        bytes memory data = "Bytes";
        uint256 projectId = 1;
        uint256 amountIn = 10 * 1e18;
        uint256 amountOut = 5 * 1e18;
        SignatureData memory signatureData = SignatureData(
            user, projectId, address(depositToken), amountOut, currentDeadline, deposit.depositReceiver(), nonce, data
        );
        bytes memory signature = _getSignature(signatureData);
        string memory func = "swap(address,address,uint256,uint256)";

        bytes memory swap = abi.encodeWithSignature(func, otherToken, depositToken, amountIn, amountOut);

        Deposit.SwapData memory swapData = Deposit.SwapData(address(router), otherToken, amountIn, swap);
        vm.startPrank(user);
        depositToken.mint(address(router), amountOut);
        otherToken.approve(address(deposit), type(uint256).max);
        otherToken.mint(user, amountIn);
        vm.expectRevert("BlastUP: router is no whitelisted");
        deposit.depositWithSwap(signature, projectId, depositToken, amountOut, currentDeadline, swapData, nonce, data);
        vm.stopPrank();
        vm.prank(admin);
        deposit.addRouter(address(router));
        vm.startPrank(user);
        vm.expectEmit(address(deposit));
        emit Deposit.Deposited(user, projectId, depositToken, amountOut, deposit.depositReceiver(), nonce, data);
        deposit.depositWithSwap(signature, projectId, depositToken, amountOut, currentDeadline, swapData, nonce, data);
        vm.stopPrank();
    }

    function test_deposit_fuzz(uint256 amount, uint256 projectId, uint256 nonce, bytes calldata data) public {
        vm.assume(amount > 0 && amount < 1e60);
        uint256 currentDeadline = block.timestamp + timeToDeadline;
        SignatureData memory signatureData = SignatureData(
            user, projectId, address(depositToken), amount, currentDeadline, deposit.depositReceiver(), nonce, data
        );
        bytes memory signature = _getSignature(signatureData);
        vm.startPrank(user);
        depositToken.mint(user, amount + 1);
        depositToken.approve(address(deposit), type(uint256).max);
        vm.expectEmit(address(deposit));
        emit Deposit.Deposited(user, projectId, depositToken, amount, deposit.depositReceiver(), nonce, data);
        deposit.deposit(signature, projectId, depositToken, amount, currentDeadline, nonce, data);
        vm.stopPrank();
    }

    function test_depositWithSwap_fuzz(
        uint256 amountOut,
        uint256 amountIn,
        uint256 projectId,
        uint256 nonce,
        bytes calldata data
    ) public {
        vm.prank(admin);
        deposit.addRouter(address(router));
        vm.assume(amountOut > 0 && amountIn > 0);

        uint256 currentDeadline = block.timestamp + timeToDeadline;
        SignatureData memory signatureData = SignatureData(
            user, projectId, address(depositToken), amountOut, currentDeadline, deposit.depositReceiver(), nonce, data
        );
        bytes memory signature = _getSignature(signatureData);
        string memory func = "swap(address,address,uint256,uint256)";

        bytes memory swap = abi.encodeWithSignature(func, otherToken, depositToken, amountIn, amountOut);

        Deposit.SwapData memory swapData = Deposit.SwapData(address(router), otherToken, amountIn, swap);
        vm.startPrank(user);
        depositToken.mint(address(router), amountOut);
        otherToken.approve(address(deposit), type(uint256).max);
        otherToken.mint(user, amountIn);
        vm.expectEmit(address(deposit));
        emit Deposit.Deposited(user, projectId, depositToken, amountOut, deposit.depositReceiver(), nonce, data);
        deposit.depositWithSwap(signature, projectId, depositToken, amountOut, currentDeadline, swapData, nonce, data);
        vm.stopPrank();
    }

    function test_withdarwFunds() public {
        vm.startPrank(user2);
        otherToken.mint(user2, 1e20);
        otherToken.transfer(address(deposit), 1e20);
        vm.assertEq(otherToken.balanceOf(address(deposit)), 1e20);
        vm.expectRevert();
        // ownable; user2 is not the owner
        deposit.withdrawFunds(address(otherToken));
        vm.stopPrank();
        vm.startPrank(admin);
        deposit.withdrawFunds(address(otherToken));
        vm.assertEq(otherToken.balanceOf(address(deposit)), 0);
        vm.stopPrank();
    }
}
