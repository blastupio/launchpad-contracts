// // SPDX-License-Identifier: UNLICENSED
// pragma solidity >=0.8.25;

// import {BaseStakingTest, Staking} from "../../BaseStaking.t.sol";

// contract StakeWithdrawClaimRewardTest is BaseStakingTest {
//     modifier setMinTimeToCWithdrawMuchGreaterThenNow() {
//         uint256 _minTimeToWithdraw = block.timestamp + 1000;

//         vm.startPrank(admin);
//         staking.setMinTimeToWithdraw(_minTimeToWithdraw);
//         vm.stopPrank();
//         _;
//     }

//     modifier stakeUSDB() {
//         vm.startPrank(user);

//         USDB.mint(user, 100 * 10 ** 19);
//         USDB.approve(address(staking), type(uint256).max);

//         staking.stake(address(USDB), 2e18);

//         vm.stopPrank();
//         _;
//     }

//     modifier stakeWETH() {
//         vm.startPrank(user);

//         WETH.mint(user, 100 * 10 ** 19);
//         WETH.approve(address(staking), type(uint256).max);

//         staking.stake(address(WETH), 2e18);

//         vm.stopPrank();
//         _;
//     }

//     function test_RevertWithdraw_Timestamp() public setMinTimeToCWithdrawMuchGreaterThenNow stakeUSDB {
//         vm.startPrank(user);

//         vm.expectRevert("BlastUP: you must wait more time");

//         staking.withdraw(address(USDB), 1e18, false);

//         vm.stopPrank();
//     }

//     function test_withdrawAll() public stakeUSDB {
//         address targetToken = address(USDB);

//         vm.startPrank(user);

//         uint256 balance = staking.getActualBalanceOfWithoutRewards(targetToken, user);
//         uint256 reward = staking.getActualRewardOf(targetToken, user);
//         uint256 rewardScaled = reward * 1e18 / staking.getActualLastIndex(targetToken);

//         staking.withdraw(targetToken, balance, false);

//         Staking.User memory userInfo = staking.getUserInfo(targetToken, user);

//         // assertEq(userInfo.lastUserIndex, 1.1e18);
//         assertEq(userInfo.totalRewards, reward);
//         assertEq(userInfo.balanceScaled, rewardScaled);

//         vm.stopPrank();
//     }
// }
