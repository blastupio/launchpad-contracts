// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseBLPStaking, BLPStaking} from "../BaseBLPStaking.t.sol";
import {BLPStakingHandler} from "./Handlers/BLPStakingHandler.sol";

contract BLPStakingInvariant is BaseBLPStaking {
    BLPStakingHandler handler;

    function setUp() public override {
        super.setUp();
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = BLPStakingHandler.stake.selector;
        selectors[1] = BLPStakingHandler.claim.selector;
        selectors[2] = BLPStakingHandler.withdraw.selector;
        selectors[3] = BLPStakingHandler.warp.selector;
        selectors[4] = BLPStakingHandler.forceWithdrawAll.selector;

        handler = new BLPStakingHandler(stakingBLP, blp);
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        excludeSender(admin);
    }

    function invariant_stakedSum() public view {
        assertGe(
            blp.balanceOf(address(stakingBLP)),
            handler.ghost_balanceForRewards() + handler.ghost_stakedSum() - handler.ghost_rewardsClaimed()
        );
    }

    function invariant_rewards() public {
        handler.forEachActor(this.assert_PreCalculatedRewardsGeRealRewards);
    }

    function assert_PreCalculatedRewardsGeRealRewards(address user) external view {
        assertGe(handler.ghost_userPreCalculatedRewards(user), handler.ghost_userRealClaimedRewards(user));
    }
}
