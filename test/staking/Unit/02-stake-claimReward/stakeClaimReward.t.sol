// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseStakingTest, YieldStaking} from "../../BaseStaking.t.sol";

contract StakeClaimRewardTest is BaseStakingTest {
    modifier stakeUSDB() {
        vm.startPrank(user);

        USDB.mint(user, 100 * 10 ** 19);
        USDB.approve(address(staking), type(uint256).max);

        staking.stake(address(USDB), 2e18);

        vm.stopPrank();
        _;
    }

    modifier stakeWETH(uint128 _amount, uint128 _amount2) {
        vm.assume(_amount > 1000 && _amount2 > 1000);

        uint256 amount = uint256(_amount);
        uint256 amount2 = uint256(_amount2);

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
        emit YieldStaking.RewardClaimed(targetToken, user, targetToken, claimableAmount);

        staking.claimReward(targetToken, targetToken, claimableAmount, false);

        vm.stopPrank();

        vm.startPrank(user2);

        (balance, claimableAmount) = staking.balanceAndRewards(targetToken, user2);

        vm.expectEmit(true, true, true, true, address(staking));
        emit YieldStaking.RewardClaimed(targetToken, user2, targetToken, claimableAmount);

        staking.claimReward(targetToken, targetToken, claimableAmount, false);

        vm.stopPrank();
    }
}
