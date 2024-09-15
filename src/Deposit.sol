// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IWETH} from "./interfaces/IWETH.sol";

contract Deposit is Ownable, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    struct SwapData {
        address router;
        IERC20 tokenIn;
        uint256 amountIn;
        bytes data;
    }

    /// @notice Address of the authorized signer
    address public signer;

    /// @notice Address of the receiver for deposited funds
    address public depositReceiver;

    /// @notice Mapping to track deposited amounts for each project and user
    mapping(uint256 projectId => mapping(address depositToken => mapping(address => uint256))) public depositedAmount;

    /// @notice Mapping to track used nonces
    mapping(uint256 => bool) public nonces;

    /// @notice Mapping to track whitelisted routers
    mapping(address => bool) public routersWhitelist;

    /// @notice Address of the wrapped native currency (e.g. WETH)
    address public immutable wNative;

    /* ========== CONSTRUCTOR ========== */

    /// @notice Initializes the contract with admin, signer, and deposit receiver addresses
    /// @param admin The address of the contract administrator
    /// @param _signer The address of the authorized signer
    /// @param _depositReceiver The address of the receiver for deposited funds
    /// @param _wNative The address of the wrapped native currency (e.g. WETH)
    constructor(address admin, address _signer, address _depositReceiver, address _wNative) Ownable(admin) {
        signer = _signer;
        depositReceiver = _depositReceiver;
        wNative = _wNative;

        emit DepositReceiverChanged(address(0), _depositReceiver);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Verifies the deposit signature and updates the deposited amount
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit
    /// @param deadline The deadline for the deposit signature
    function _beforeDeposit(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        uint256 nonce,
        address to,
        bytes calldata data
    ) internal {
        require(!nonces[nonce], "BlastUP: this nonce is already used");
        require(block.timestamp <= deadline, "BlastUP: the deadline for this signature has passed");

        address signer_ = keccak256(
            abi.encodePacked(
                msg.sender, projectId, depositToken, amount, address(this), block.chainid, deadline, nonce, data
            )
        ).toEthSignedMessageHash().recover(signature);
        require(signer_ == signer, "BlastUP: signature verification failed");

        depositedAmount[projectId][address(depositToken)][to] += amount;
        nonces[nonce] = true;

        emit Deposited(to, projectId, depositToken, amount, depositReceiver, nonce, data);
    }

    /* ========== FUNCTIONS ========== */

    /// @notice Pauses the contract, disabling certain functions
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract, enabling certain functions
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Sets a new signer address
    /// @param _signer The new signer address
    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    /// @notice Sets a new deposit receiver address
    /// @param _depositReceiver The new deposit receiver address
    function setDepositReceiver(address _depositReceiver) external onlyOwner {
        emit DepositReceiverChanged(depositReceiver, _depositReceiver);
        depositReceiver = _depositReceiver;
    }

    /// @notice Adds a router to the whitelist
    /// @param router The router address to add
    function addRouter(address router) external onlyOwner {
        routersWhitelist[router] = true;
    }

    /// @notice Removes a router from the whitelist
    /// @param router The router address to remove
    function removeRouter(address router) public onlyOwner {
        routersWhitelist[router] = false;
    }

    /// @notice Swaps exact amount of tokenIn to tokenOut, expecting to receive at least `neededAmountOut`.
    /// After swap, `neededAmountOut` is transferred to `receiver` and leftover is sent back to `msg.sender`.
    /// @param router The router address to use for the swap
    /// @param data The data for the swap
    /// @param receiver The address to receive the swapped tokens
    /// @param tokenIn The token to swap from
    /// @param amountIn The amount of tokenIn to swap
    /// @param tokenOut The token to swap to
    /// @param neededAmountOut The amount of tokenOut to receive
    function _swap(
        address router,
        bytes calldata data,
        address receiver,
        IERC20 tokenIn,
        uint256 amountIn,
        IERC20 tokenOut,
        uint256 neededAmountOut
    ) internal {
        // Swap tokenIn to depositToken
        require(routersWhitelist[router], "BlastUP: router is not whitelisted");
        tokenIn.forceApprove(router, amountIn);
        (bool success,) = router.call(data);
        require(success, "BlastUP: swap failed");

        uint256 amountOut = tokenOut.balanceOf(address(this));
        require(amountOut >= neededAmountOut, "BlastUP: amount out lt amount");

        // Send the remaining amount back to the sender
        if (amountOut > neededAmountOut) tokenOut.safeTransfer(msg.sender, amountOut - neededAmountOut);
        tokenOut.safeTransfer(receiver, neededAmountOut);
    }

    /// @notice Wraps native currency to wNative
    /// @param amount The amount of native currency to wrap
    function _wrapNative(uint256 amount) internal {
        (bool success,) = payable(wNative).call{value: amount}("");
        require(success, "BlastUP: failed to wrap native");
    }

    /// @notice Deposits tokens to the specified project
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit
    /// @param deadline The deadline for the deposit signature
    /// @param nonce The unique nonce for the deposit
    /// @param data Additional data for the deposit
    function deposit(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        uint256 nonce,
        address to,
        bytes calldata data
    ) external whenNotPaused {
        _beforeDeposit(signature, projectId, depositToken, amount, deadline, nonce, to, data);
        depositToken.safeTransferFrom(msg.sender, depositReceiver, amount);
    }

    /// @notice Deposits tokens to the specified project with an additional token swap
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit
    /// @param deadline The deadline for the deposit signature
    /// @param swapData The data for the token swap
    /// @param nonce The unique nonce for the deposit
    /// @param data Additional data for the deposit
    function depositWithSwap(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        SwapData calldata swapData,
        uint256 nonce,
        address to,
        bytes calldata data
    ) external whenNotPaused {
        _beforeDeposit(signature, projectId, depositToken, amount, deadline, nonce, to, data);
        swapData.tokenIn.safeTransferFrom(msg.sender, address(this), swapData.amountIn);
        _swap(
            swapData.router, swapData.data, depositReceiver, swapData.tokenIn, swapData.amountIn, depositToken, amount
        );
    }

    /// @notice Deposits native currency to the specified project
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param deadline The deadline for the deposit signature
    /// @param nonce The unique nonce for the deposit
    /// @param data Additional data for the deposit
    function depositNative(
        bytes calldata signature,
        uint256 projectId,
        uint256 deadline,
        uint256 nonce,
        address to,
        bytes calldata data
    ) external payable whenNotPaused {
        _beforeDeposit(signature, projectId, IERC20(wNative), msg.value, deadline, nonce, to, data);
        _wrapNative(msg.value);
        IERC20(wNative).safeTransfer(depositReceiver, msg.value);
    }

    /// @notice Deposits native currency to the specified project
    /// @param signature The signature to verify
    /// @param projectId The ID of the project to deposit to
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens to deposit which is expected to be received after swap.
    /// @param deadline The deadline for the deposit signature
    /// @param router Router to use for the swap
    /// @param routerData Data to use for the swap
    /// @param nonce The unique nonce for the deposit
    /// @param data Additional data for the deposit
    function depositNativeWithSwap(
        bytes calldata signature,
        uint256 projectId,
        IERC20 depositToken,
        uint256 amount,
        uint256 deadline,
        address router,
        bytes calldata routerData,
        uint256 nonce,
        address to,
        bytes calldata data
    ) external payable whenNotPaused {
        _beforeDeposit(signature, projectId, depositToken, amount, deadline, nonce, to, data);
        _wrapNative(msg.value);
        _swap(router, routerData, depositReceiver, IERC20(wNative), msg.value, depositToken, amount);
    }

    /// @notice Withdraws funds accidentally sent to the contract
    /// @param token The address of the token to withdraw
    function withdrawFunds(address token) external onlyOwner {
        if (token == address(0)) {
            (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
            require(success, "BlastUP: failed to send ETH");
        } else {
            IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
        }
    }

    /// @notice Fallback function to prevent accidental ETH transfers
    receive() external payable {
        revert("BlastUP: you can not send eth to this contract");
    }

    /* ========== EVENTS ========== */

    /// @notice Emitted when tokens are deposited to a project
    /// @param buyer The address of the buyer
    /// @param indexedProjectId The ID of the project
    /// @param depositToken The token being deposited
    /// @param amount The amount of tokens deposited
    /// @param depositReceiver The address of the deposit receiver
    /// @param nonce The unique nonce for the deposit
    /// @param data Additional data for the deposit
    event Deposited(
        address indexed buyer,
        uint256 indexed indexedProjectId,
        IERC20 depositToken,
        uint256 amount,
        address depositReceiver,
        uint256 nonce,
        bytes indexed data
    );

    /// @notice Emitted when the deposit receiver address is changed
    /// @param oldDepositReceiver The old deposit receiver address
    /// @param newDepositReceiver The new deposit receiver address
    event DepositReceiverChanged(address oldDepositReceiver, address newDepositReceiver);
}
