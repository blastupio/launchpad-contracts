// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseStakingTest, Staking} from "../../BaseStaking.t.sol";

contract StakeClaimRewardTest is BaseStakingTest {
    // modifier setMinTimeToClaimMuchGreaterThenNow() {
    //     uint256 _minTimeToClaim = block.timestamp + 1000;

    //     vm.startPrank(admin);
    //     staking.setMinTimeToClaim(_minTimeToClaim);
    //     vm.stopPrank();
    //     _;
    // }

    // modifier setMinTimeToClaimToZero() {
    //     uint256 _minTimeToClaim = 0;

    //     vm.startPrank(admin);
    //     staking.setMinTimeToClaim(0);
    //     vm.stopPrank();
    //     _;
    // }

    modifier stakeUSDB() {
        vm.startPrank(user);

        USDB.mint(user, 100 * 10 ** 19);
        USDB.approve(address(staking), type(uint256).max);

        staking.stake(address(USDB), 2e18);

        vm.stopPrank();
        _;
    }

    modifier stakeWETH(uint128 amount, uint128 amount2) {
        vm.assume(amount > 1000 && amount2 > 1000);

        uint256 amount = uint256(amount);
        uint256 amount2 = uint256(amount);

        vm.startPrank(user);

        WETH.mint(user, amount + 1);
        WETH.approve(address(staking), type(uint256).max);

        staking.stake(address(WETH), amount);

        vm.stopPrank();

        vm.startPrank(user2);

        WETH.mint(user2, amount2 + 1);
        WETH.approve(address(staking), type(uint256).max);

        staking.stake(address(WETH), amount2);

        vm.stopPrank();
        _;
    }

    function test_claimReward_fuzz(uint128 amount, uint128 amount2) public stakeWETH(amount, amount2) {
        address targetToken = address(WETH);

        vm.startPrank(user);

        (uint256 balance, uint256 claimableAmount) = staking.balanceAndRewards(targetToken, user);

        vm.expectEmit(true, true, true, true, address(staking));
        emit Staking.RewardClaimed(targetToken, user, targetToken, claimableAmount);

        staking.claimReward(targetToken, targetToken, claimableAmount, false);

        vm.stopPrank();

        vm.startPrank(user2);

        (balance, claimableAmount) = staking.balanceAndRewards(targetToken, user2);

        vm.expectEmit(true, true, true, true, address(staking));
        emit Staking.RewardClaimed(targetToken, user2, targetToken, claimableAmount);

        staking.claimReward(targetToken, targetToken, claimableAmount, false);

        vm.stopPrank();
    }

    // function test_RevertStakeClaimReward() public setMinTimeToClaimMuchGreaterThenNow stakeUSDB {
    //     vm.startPrank(user);

    //     uint256 claimableAmount = staking.getActualRewardOf(address(USDB), user);

    //     vm.expectRevert("BlastUP: you must wait more time");

    //     staking.claimReward(address(USDB), address(USDB), claimableAmount, false);

    //     vm.stopPrank();

    // }

    // function test_RevertStakeClaimReward_RewardAmountGtTotalRewards() public stakeUSDB {
    //     vm.startPrank(user);

    //     uint256 claimableAmount = 1e18;

    //     vm.expectRevert("BlastUP: you do not have enough rewards");

    //     staking.claimReward(address(USDB), address(USDB), claimableAmount, false);

    //     vm.stopPrank();
    // }

    // function test_ClaimReward_USDB() public stakeUSDB {
    //     vm.startPrank(user);

    //     uint256 claimableAmount = staking.getActualRewardOf(address(USDB), user);

    //     vm.expectEmit(true, true, true, true, address(staking));
    //     emit Staking.RewardClaimed(address(USDB), user, address(USDB), claimableAmount);

    //     staking.claimReward(address(USDB), address(USDB), claimableAmount, false);

    //     // Staking.StakingInfo storage check = staking.stakingInfos[address(USDB)];
    //     Staking.User memory checkUser = staking.getUserInfo(address(USDB), user);

    //     assertEq(checkUser.lastUserIndex, 1.1e18);
    //     assertEq(checkUser.totalRewards, 0);
    //     assertEq(staking.getActualBalanceOfWithRewards(address(USDB), user), 2e18);

    //     vm.stopPrank();
    // }

    // function test_ClaimReward_WETH() public stakeWETH {
    //     address targetToken = address(WETH);

    //     vm.startPrank(user);

    //     uint256 claimableAmount = staking.getActualRewardOf(targetToken, user);

    //     vm.expectEmit(true, true, true, true, address(staking));
    //     emit Staking.RewardClaimed(targetToken, user, targetToken, claimableAmount);

    //     staking.claimReward(targetToken, targetToken, claimableAmount, false);

    //     vm.stopPrank();
    // }

    // function test_ClaimReward_ETH() public stakeWETH {
    //     address targetToken = address(WETH);
    //     vm.deal(targetToken, 1e19);

    //     vm.startPrank(user);

    //     uint256 claimableAmount = staking.getActualRewardOf(targetToken, user);

    //     vm.expectEmit(true, true, true, true, address(staking));

    //     emit Staking.RewardClaimed(targetToken, user, targetToken, claimableAmount);

    //     staking.claimReward(targetToken, targetToken, claimableAmount, true);

    //     vm.stopPrank();
    // }
}
