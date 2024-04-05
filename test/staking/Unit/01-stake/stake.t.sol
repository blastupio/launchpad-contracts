// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseStakingTest, Staking, WadMath} from "../../BaseStaking.t.sol";

contract StakeTest is BaseStakingTest {
    using WadMath for uint256;
    // error InvalidTokenForStaking(address token);

    function test_RevertStake_InactivePool() public {
        vm.startPrank(user);

        testToken.mint(user, 100 * 10 ** 19);
        testToken.approve(address(staking), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(Staking.InvalidPool.selector, address(testToken)));

        staking.stake(address(testToken), 10e18);
        vm.stopPrank();
    }

    function test_StakeUSDB() public {
        uint256 amount = 2e18;

        vm.startPrank(user);

        USDB.mint(user, 100 * 10 ** 19);
        USDB.approve(address(staking), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(staking));
        emit Staking.Staked(address(USDB), user, amount);

        staking.stake(address(USDB), amount);

        // assertEq(staking.getActualLastIndex(address(USDB)), 1.1e18);
        // assertEq(staking.getActualtotalSupply(address(USDB)), amount);
        // assertEq(staking.getActualBalanceOfWithRewards(address(USDB), user), amount);
        // assertEq(staking.rewardOf(address(USDB), user), 0);

        vm.stopPrank();
    }

    function test_StakeUSDB_fuzz(uint128 amount, uint128 amount2) public {
        vm.assume(amount > 1000 && amount2 > 1000);

        uint256 amount = uint256(amount);
        uint256 amount2 = uint256(amount);

        vm.startPrank(user);

        USDB.mint(user, amount + 1);
        USDB.approve(address(staking), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(staking));
        emit Staking.Staked(address(USDB), user, amount);

        staking.stake(address(USDB), amount);

        Staking.User memory userInfo = staking.userInfo(address(USDB), user);

        assertEq(userInfo.amountDeposited + userInfo.remainders, amount);
        assertEq(block.timestamp, userInfo.timestampToWithdraw);

        vm.stopPrank();

        vm.startPrank(user2);

        USDB.mint(user2, amount2 + 1);
        USDB.approve(address(staking), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(staking));
        emit Staking.Staked(address(USDB), user2, amount2);

        staking.stake(address(USDB), amount2);

        userInfo = staking.userInfo(address(USDB), user2);

        assertEq(userInfo.amountDeposited + userInfo.remainders, amount2);
        assertEq(block.timestamp, userInfo.timestampToWithdraw);

        vm.stopPrank();
    }

    function test_StakeWETH() public {
        uint256 amount = 2e18;

        vm.startPrank(user);

        WETH.mint(user, 100 * 10 ** 19);
        WETH.approve(address(staking), type(uint256).max);

        vm.expectEmit(true, true, true, true, address(staking));
        emit Staking.Staked(address(WETH), user, amount);

        staking.stake(address(WETH), amount);

        // assertEq(staking.getLastIndex(address(WETH)), 1e18);
        // assertEq(staking.totalSupply(address(WETH)), amount);
        // assertEq(staking.balanceOfWithRewards(address(WETH), user), amount);
        // assertEq(staking.rewardOf(address(WETH), user), 0);

        vm.stopPrank();
    }

    function test_StakeETH() public {
        uint256 amount = 2e18;

        vm.startPrank(user);
        vm.deal(user, 10e18);

        staking.stake{value: amount}(address(0), 0);

        // assertEq(staking.getLastIndex(address(WETH)), 1e18);
        // assertEq(staking.totalSupply(address(WETH)), amount);
        // assertEq(staking.balanceOfWithRewards(address(WETH), user), amount);
        // assertEq(staking.rewardOf(address(WETH), user), 0);

        vm.stopPrank();
    }

    modifier setMinAmount100USDB() {
        vm.prank(admin);
        staking.setMinUSDBStakeValue(100e18);
        vm.stopPrank();
        _;
    }

    function test_RevertStake_USDB() public setMinAmount100USDB {
        uint256 amount = 5e18;

        vm.startPrank(user);

        USDB.mint(user, 100 * 10 ** 19);
        USDB.approve(address(staking), type(uint256).max);

        vm.expectRevert("BlastUp: you must send more to stake");

        staking.stake(address(USDB), amount);

        vm.stopPrank();
    }

    function test_RevertStake_WETH() public setMinAmount100USDB {
        uint256 amount = 0.5e18;
        vm.startPrank(user);

        WETH.mint(user, 100 * 10 ** 19);
        WETH.approve(address(staking), type(uint256).max);

        vm.expectRevert("BlastUp: you must send more to stake");

        staking.stake(address(WETH), amount);

        vm.stopPrank();
    }

    function test_RevertStake_ETH() public setMinAmount100USDB {
        uint256 amount = 0.5e18;

        vm.startPrank(user);
        vm.deal(user, 10e18);

        vm.expectRevert("BlastUp: you must send more to stake");

        staking.stake{value: amount}(address(0), 0);

        vm.stopPrank();
    }
}
