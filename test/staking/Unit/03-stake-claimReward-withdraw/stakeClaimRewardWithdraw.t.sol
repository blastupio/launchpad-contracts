// // SPDX-License-Identifier: UNLICENSED
// pragma solidity >=0.8.25;

// import {BaseStakingTest, Staking} from "../../BaseStaking.t.sol";

// contract StakeClaimRewardWithdrawTest is BaseStakingTest {
//     modifier setMinTimeToWithdrawMuchGreaterThenNow() {
//         uint256 _minTimeToClaim = block.timestamp + 1000;

//         vm.startPrank(admin);
//         staking.setMinTimeToWithdraw(_minTimeToClaim);
//         vm.stopPrank();
//         _;
//     }

//     modifier stakeAndClaimUSDB() {
//         vm.startPrank(user);

//         USDB.mint(user, 100 * 10 ** 19);
//         USDB.approve(address(staking), type(uint256).max);

//         staking.stake(address(USDB), 2e18);
//         staking.claimReward(address(USDB), address(USDB), staking.getActualRewardOf(address(USDB), user), false);

//         vm.stopPrank();
//         _;
//     }

//     modifier stakeAndClaimWETH() {
//         vm.startPrank(user);

//         WETH.mint(user, 100 * 10 ** 19);
//         WETH.approve(address(staking), type(uint256).max);

//         staking.stake(address(WETH), 2e18);
//         staking.claimReward(address(WETH), address(WETH), staking.getActualRewardOf(address(WETH), user), false);

//         vm.stopPrank();
//         _;
//     }

//     function test_RevertWithdraw_InvalidPool() public stakeAndClaimUSDB {
//         vm.startPrank(user);

//         vm.expectRevert(abi.encodeWithSelector(Staking.InvalidPool.selector, address(testToken)));

//         staking.withdraw(address(testToken), 1e18, false);

//         vm.stopPrank();
//     }

//     // function test_RevertWithdraw_Timestamp() public setMinTimeToClaimMuchGreaterThenNow stakeAndClaimUSDB {
//     //     vm.startPrank(user);

//     //     vm.expectRevert("BlastUP: you must wait more time");

//     //     staking.withdraw(address(USDB), 1e18, false);

//     //     vm.stopPrank();
//     // }

//     function test_RevertWithdraw_AmountGtThenBalance() public stakeAndClaimUSDB {
//         vm.startPrank(user);

//         vm.expectRevert("BlastUP: you do not have enough balance");

//         staking.withdraw(address(USDB), 3e18, false);

//         vm.stopPrank();
//     }

//     // function test_withdraw() public stakeAndClaimUSDB {

//     // }
// }
