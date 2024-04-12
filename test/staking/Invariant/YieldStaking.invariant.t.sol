// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseStakingTest, Staking, WadMath} from "../BaseStaking.t.sol";
import {StakingHandler} from "./Handlers/StakingHandler.sol";

contract StakingInvariant is BaseStakingTest {
    StakingHandler handler;

    function setUp() public override {
        super.setUp();
        handler = new StakingHandler(staking, address(USDB), address(WETH));

        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = StakingHandler.stake.selector;
        selectors[1] = StakingHandler.withdraw.selector;
        selectors[2] = StakingHandler.claimReward.selector;
        selectors[3] = StakingHandler.setMinUSDBStakeValue.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        excludeContract(address(WETH));
        excludeContract(address(USDB));

        excludeSender(admin);
    }

    function invariant_balanceEqStakedPlusClaimed() public view {
        assertGe(USDB.balanceOf(address(staking)), handler.ghost_stakedSums(address(USDB)));
        assertGe(WETH.balanceOf(address(staking)), handler.ghost_stakedSums(address(WETH)));
    }

    // function invariant_callSummary() public view {
    //     handler.callSummary();
    // }
}
