// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseBLPStaking, BLPStaking} from "../BaseBLPStaking.t.sol";
import {BLPStakingHandler} from "./Handlers/BLPStakingHandler.sol";

contract BLPStakingInvariant is BaseBLPStaking {
    BLPStakingHandler handler;

    function setUp() public override {
        super.setUp();
        handler = new BLPStakingHandler(stakingBLP, blp);
        targetContract(address(handler));
        excludeSender(admin);
    }

    function invariant_stakedSum() public view {
        assertGe(
            blp.balanceOf(address(stakingBLP)),
            initialBalanceOfStaking + handler.ghost_stakedSum() - handler.ghost_rewardsClaimed()
        );
    }
}
