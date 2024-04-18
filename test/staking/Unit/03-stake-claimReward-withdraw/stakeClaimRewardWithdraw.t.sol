// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseStakingTest, YieldStaking, IERC20} from "../../BaseStaking.t.sol";

contract StakeClaimRewardWithdrawTest is BaseStakingTest {
    modifier setMinTimeToWithdrawMuchGreaterThenNow() {
        uint256 _minTimeToClaim = block.timestamp + 1000;

        vm.prank(admin);
        staking.setMinTimeToWithdraw(_minTimeToClaim);
        _;
    }

    modifier stakeAndClaimUSDB() {
        vm.startPrank(user);
        USDB.mint(user, 100 * 10 ** 19);
        USDB.approve(address(staking), type(uint256).max);

        staking.stake(address(USDB), 2e18);
        (, uint256 reward) = staking.balanceAndRewards(address(USDB), user);
        staking.claimReward(address(USDB), address(USDB), reward, false);
        vm.stopPrank();
        _;
    }

    modifier stakeAndClaimWETH() {
        vm.startPrank(user);
        WETH.mint(user, 100 * 10 ** 19);
        WETH.approve(address(staking), type(uint256).max);

        staking.stake(address(WETH), 2e18);
        (, uint256 reward) = staking.balanceAndRewards(address(WETH), user);
        staking.claimReward(address(WETH), address(WETH), reward, false);
        vm.stopPrank();
        _;
    }

    modifier stakeFuzz(uint256 amount, uint256 amount2, uint256 amount3) {
        uint256 amount4;

        amount = bound(amount, 10, 1e36);
        amount2 = bound(amount2, 10, 1e36);
        amount3 = bound(amount3, 10, 1e36);
        amount4 = amount3 + amount2 + 7;
        amount4 = bound(amount4, 10, 1e36);

        // user
        USDB.mint(user, amount);
        vm.prank(user);
        USDB.approve(address(staking), amount);

        // user2
        vm.deal(address(WETH), amount2);
        WETH.mint(user2, amount2);
        vm.prank(user2);
        WETH.approve(address(staking), amount2);

        // user3
        vm.deal(user3, amount3);

        // user4
        USDB.mint(user4, amount4);
        vm.prank(user4);
        USDB.approve(address(staking), amount4);

        // stake
        vm.prank(user);
        staking.stake(address(USDB), amount);

        vm.prank(user2);
        staking.stake(address(WETH), amount2);

        vm.prank(user3);
        staking.stake{value: amount3}(address(192838), 0);

        vm.prank(user4);
        staking.stake(address(USDB), amount4);
        _;
    }

    function _checkClaimReward(address _user, address _token, bool _getETH) internal {
        (, uint256 reward) = staking.balanceAndRewards(_token, _user);
        uint256 balanceOfUserBefore = _getETH ? _user.balance : IERC20(_token).balanceOf(_user);
        vm.prank(_user);
        staking.claimReward(_token, _token, reward, _getETH);
        if (_getETH) {
            assertEq(balanceOfUserBefore + reward, _user.balance);
        } else {
            assertEq(balanceOfUserBefore + reward, IERC20(_token).balanceOf(_user));
        }
    }

    function test_RevertWithdraw_InvalidPool() public stakeAndClaimUSDB {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(YieldStaking.InvalidPool.selector, address(testToken)));

        staking.withdraw(address(testToken), 1e18, false);
        vm.stopPrank();
    }

    function test_RevertWithdraw_ByTimestamp() public setMinTimeToWithdrawMuchGreaterThenNow stakeAndClaimUSDB {
        vm.startPrank(user);
        (uint256 balance,) = staking.balanceAndRewards(address(USDB), user);

        vm.expectRevert("BlastUP: you must wait more time");
        staking.withdraw(address(USDB), balance, false);
        vm.stopPrank();
    }

    function test_RevertWithdraw_InsufficientBalance() public stakeAndClaimUSDB {
        vm.startPrank(user);
        (uint256 balance,) = staking.balanceAndRewards(address(USDB), user);

        vm.expectRevert("BlastUP: you do not have enough balance");
        staking.withdraw(address(USDB), balance + 10, false);
        vm.stopPrank();
    }

    function test_WithdrawClaimFuzz(uint256 amount, uint256 amount2, uint256 amount3)
        public
        stakeFuzz(amount, amount2, amount3)
    {
        _checkClaimReward(user, address(USDB), false);
        _checkClaimReward(user2, address(WETH), true);
        _checkClaimReward(user3, address(WETH), false);
        _checkClaimReward(user4, address(USDB), false);
    }
}
