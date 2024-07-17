// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Mock} from "../../src/mocks/ERC20Mock.sol";
import {Vesting} from "../../src/Vesting.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VestingTest is Test {
    address internal admin;
    uint256 internal adminPrivateKey;

    address user;
    address user2;
    address user3;
    address operator;

    ERC20Mock token;
    Vesting launchpad;

    uint256 intitialTgeTimestamp;
    uint256 initialVestingStart;
    uint256 initialVestingDuration;
    uint8 initialTgePercent;

    function setUp() public virtual {
        adminPrivateKey = 0xa11ce;
        admin = vm.addr(adminPrivateKey);
        user = address(10);
        user2 = address(11);
        user3 = address(12);
        operator = address(13);

        intitialTgeTimestamp = 1000;
        initialVestingStart = 2000;
        initialVestingDuration = 6000;
        initialTgePercent = 10;

        vm.startPrank(admin);
        token = new ERC20Mock("Token", "TKN", 18);
        launchpad = new Vesting(
            admin,
            operator,
            address(token),
            intitialTgeTimestamp,
            initialVestingStart,
            initialVestingDuration,
            initialTgePercent
        );
        vm.stopPrank();
    }

    function test_setters() public {
        vm.startPrank(admin);
        launchpad.setTgePercent(20);
        vm.assertEq(launchpad.tgePercent(), 20);

        vm.warp(100);
        vm.expectRevert("BlastUP: invalid tge timestamp");
        launchpad.setTgeTimestamp(block.timestamp - 10);
        vm.expectRevert("BlastUP: invalid vesting start");
        launchpad.setVestingStart(block.timestamp - 20);

        launchpad.setTgeTimestamp(1100);
        vm.assertEq(launchpad.tgeTimestamp(), 1100);
        launchpad.setVestingStart(2200);
        vm.assertEq(launchpad.vestingStart(), 2200);
        launchpad.setVestingDuration(15000);
        vm.assertEq(launchpad.vestingDuration(), 15000);

        vm.assertEq(launchpad.operator(), operator);
        launchpad.setOperator(user2);
        vm.assertEq(launchpad.operator(), user2);

        vm.assertEq(address(launchpad.token()), address(token));
        vm.stopPrank();
    }

    function test_setAndClaimFuzz(uint8 usersQuantity, uint160 rand) public {
        vm.assume(usersQuantity > 0);
        vm.assume(rand > 0);
        address[] memory users = new address[](usersQuantity);
        uint256[] memory balances = new uint256[](usersQuantity);
        uint256 totalAmount;
        for (uint8 i = 0; i < usersQuantity; i++) {
            uint256 random = uint256(rand) * usersQuantity % 1461501637330902918203684832716283019655932542075 + 20 + i;
            users[i] = address(uint160(random));
            uint256 newAmount = random % 2 ** 64 + 1;
            vm.assume(newAmount != 0);
            balances[i] = newAmount;
            totalAmount += newAmount;
        }

        vm.startPrank(admin);
        token.mint(address(launchpad), totalAmount);
        launchpad.setBalances(users, balances);
        vm.stopPrank();
        for (uint8 i = 0; i < usersQuantity; i++) {
            vm.warp(block.timestamp + i % 100 + 1);
            vm.startPrank(users[i]);
            uint256 claimableAmount = launchpad.getClaimableAmount(users[i]);
            if (claimableAmount > 0 && launchpad.tgeTimestamp() < block.timestamp) {
                launchpad.claim();
                vm.assertGt(token.balanceOf(users[i]), 0);
                (uint256 claimedAmount, uint256 balance) = launchpad.users(users[i]);
                vm.assertLe(token.balanceOf(users[i]), balance);
                vm.assertLe(claimedAmount, balance);
            }
            vm.stopPrank();
        }
    }
}
