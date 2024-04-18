// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseBLPStaking, ERC20Mock, BLPStaking} from "../BaseBLPStaking.t.sol";

contract BLPWithdrawClaimTest is BaseBLPStaking {
    modifier stake() {
        uint256 amount = 1e18;
        uint256 lockTime = 100;

        blp.mint(user, amount);

        vm.prank(admin);
        stakingBLP.setLockTimeToPercent(lockTime, 10);

        vm.startPrank(user);
        blp.approve(address(stakingBLP), amount);
        stakingBLP.stake(amount, lockTime);
        vm.stopPrank();
        _;
    }

    modifier stakeFuzz(uint256 amount, uint256 lockTime, uint8 percent) {
        amount = bound(amount, 1e5, 1e40);
        percent = uint8(bound(percent, 1, 200));
        lockTime = bound(lockTime, 1e4, 1e15);

        blp.mint(user, amount);

        vm.prank(admin);
        stakingBLP.setLockTimeToPercent(lockTime, percent);

        vm.startPrank(user);
        blp.approve(address(stakingBLP), amount);
        stakingBLP.stake(amount, lockTime);
        vm.stopPrank();
        vm.warp(lockTime * 1e5);
        _;
    }

    function test_claimFuzz(uint256 amount, uint256 lockTime, uint8 percent)
        public
        stakeFuzz(amount, lockTime, percent)
    {
        uint256 reward = stakingBLP.getRewardOf(user);
        vm.assume(reward > 0);

        vm.prank(user);
        vm.expectEmit(address(stakingBLP));
        emit BLPStaking.Claimed(user, reward);
        stakingBLP.claim();

        assertEq(blp.balanceOf(user), reward);
    }

    function test_RevertWithdraw_UnlockTimestamp() public stake {
        vm.prank(user);
        vm.expectRevert("BlastUP: you must wait more to withdraw");
        stakingBLP.withdraw();
    }

    function test_withdrawFuzz(uint256 amount, uint256 lockTime, uint8 percent)
        public
        stakeFuzz(amount, lockTime, percent)
    {
        uint256 reward = stakingBLP.getRewardOf(user);
        vm.assume(reward > 0);
        (uint256 balance,,,) = stakingBLP.users(user);

        vm.prank(user);
        stakingBLP.withdraw();

        assertEq(blp.balanceOf(user), balance + reward);
    }
}
