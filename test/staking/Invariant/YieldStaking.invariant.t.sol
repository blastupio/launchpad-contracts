// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseStakingTest, YieldStaking, WadMath} from "../BaseStaking.t.sol";
import {StakingHandler} from "./Handlers/StakingHandler.sol";

contract StakingInvariant is BaseStakingTest {
    StakingHandler handler;

    function setUp() public override {
        super.setUp();
        handler = new StakingHandler(staking, address(USDB), address(WETH));
        targetContract(address(handler));
        excludeSender(admin);
        address stakingProxyAdmin = vm.computeCreateAddress(address(staking), 1);
        excludeSender(stakingProxyAdmin);
    }

    function invariant_sumBalances() public view {
        address[] memory actors = handler.getActors();
        uint256 sumUSDB;
        uint256 sumWETH;
        for (uint256 i = 0; i < actors.length; i++) {
            sumWETH += handler.getUserBalance(address(WETH), actors[i]);
            sumUSDB += handler.getUserBalance(address(USDB), actors[i]);
        }
        assertGe(USDB.balanceOf(address(staking)) + USDB.getClaimableAmount(address(staking)), sumUSDB);
        assertGe(WETH.balanceOf(address(staking)) + WETH.getClaimableAmount(address(staking)), sumWETH);
    }
}
