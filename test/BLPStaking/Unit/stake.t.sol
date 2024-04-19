// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseBLPStaking, BLPStaking} from "../BaseBLPStaking.t.sol";

contract BLPStakeTest is BaseBLPStaking {
    function test_RevertStake_invalidLockTime() public {
        uint256 amount = 1e18;
        blp.mint(user, amount);
        vm.prank(user);
        blp.approve(address(stakingBLP), amount);

        vm.prank(user);
        vm.expectRevert("BlastUP: invalid lockTime");
        stakingBLP.stake(amount, 1);

        vm.prank(admin);
        stakingBLP.setLockTimeToPercent(1e10, 15);

        vm.prank(user);
        vm.expectRevert("BlastUP: invalid lockTime");
        stakingBLP.stake(amount, 10);
    }

    function test_RevertStake_BalanceMustBeGtMin() public {
        uint256 amount = 1e8;
        uint256 lockTime = 10;
        blp.mint(user, amount);
        vm.prank(user);
        blp.approve(address(stakingBLP), amount);

        vm.startPrank(admin);
        stakingBLP.setLockTimeToPercent(lockTime, 10);
        stakingBLP.setMinBalance(1e10);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("BlastUP: you must send more to stake");
        stakingBLP.stake(amount, lockTime);
    }

    function test_stake() public {
        uint256 amount = 1e18;
        uint256 lockTime = 100;

        blp.mint(user, amount);

        vm.prank(admin);
        stakingBLP.setLockTimeToPercent(lockTime, 10);

        vm.startPrank(user);
        blp.approve(address(stakingBLP), amount);
        vm.expectEmit(address(stakingBLP));
        emit BLPStaking.Staked(user, amount);
        stakingBLP.stake(amount, lockTime);
        assertEq(stakingBLP.totalLocked(), amount);

        vm.warp(1e5);
        assertGt(stakingBLP.getRewardOf(user), 0);
    }

    function test_stakeFuzz(uint256 amount, uint256 lockTime, uint32 percent) public {
        vm.warp(1001);
        amount = bound(amount, 1e6, 1e40);
        percent = uint32(bound(percent, 10_000, 2_000_000));
        lockTime = bound(lockTime, 1e4, 1e15);

        blp.mint(user, amount);

        vm.prank(admin);
        stakingBLP.setLockTimeToPercent(lockTime, percent);

        vm.startPrank(user);
        blp.approve(address(stakingBLP), amount);
        vm.expectEmit(address(stakingBLP));
        emit BLPStaking.Staked(user, amount);
        stakingBLP.stake(amount, lockTime);
        vm.stopPrank();
        assertEq(stakingBLP.totalLocked(), amount);
        vm.prank(admin);
        vm.expectRevert("BlastUP: amount gt allowed to be withdrawn");
        stakingBLP.withdrawFunds(amount);

        uint256 reward = stakingBLP.getRewardOf(user);
        assertEq(reward, 0);

        vm.warp(lockTime * 1e6);
        assertGt(stakingBLP.getRewardOf(user), 0);
    }
}
