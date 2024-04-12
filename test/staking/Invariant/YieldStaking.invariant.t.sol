// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseStakingTest, Staking, WadMath} from "../BaseStaking.t.sol";
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

    function invariant_balanceEqStakedPlusClaimed() public view {
        assertGe(USDB.balanceOf(address(staking)), handler.ghost_stakedSums(address(USDB)));
        assertGe(WETH.balanceOf(address(staking)), handler.ghost_stakedSums(address(WETH)));
    }

    // function invariant_callSummary() public view {
    //     handler.callSummary();
    // }
}
