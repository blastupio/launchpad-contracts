// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseLaunchpadTest, Launchpad, Types} from "../BaseLaunchpad.t.sol";
import {LaunchpadHandler} from "./Handlers/LaunchpadHandler.sol";

contract LaunchpadInvariant is BaseLaunchpadTest {
    LaunchpadHandler handler;

    function setUp() public override {
        super.setUp();
        handler = new LaunchpadHandler(launchpad, address(USDB), address(WETH), adminPrivateKey);

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = LaunchpadHandler.buyTokens.selector;
        selectors[1] = LaunchpadHandler.claimTokens.selector;
        selectors[2] = LaunchpadHandler.claimRemainders.selector;
        selectors[3] = LaunchpadHandler.placeTokens.selector;
        selectors[4] = LaunchpadHandler.setVestingStart.selector;
        selectors[5] = LaunchpadHandler.setTgeStart.selector;
        selectors[6] = LaunchpadHandler.setSaleEnd.selector;
        selectors[7] = LaunchpadHandler.setFCFSSaleStart.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
        excludeContract(address(WETH));
        excludeContract(address(USDB));

        excludeSender(admin);
    }

    function invariant_sendedAmount() public {
        handler.forEachToken(this.assertAddressForCollectedBalanceGteSendedAmount);
    }

    function invariant_boughtAmount() public {
        handler.forEachToken(this.assertAddressBoughtAmountLeInitialVolume);
    }

    function invariant_allowedAllocations() public {
        handler.forEachToken(this.assertSumUsersAllowedAllocationLeInitialVolume);
    }

    function invariant_claimedAmount() public {
        handler.forEachToken(this.assertClaimedAmountLeBoughtAmount);
    }

    function assertClaimedAmountLeBoughtAmount(address token) public view {
        LaunchpadHandler.PlacedTokenInvariants memory placedTokenInvariant = handler.getPlacedTokenInvariants(token);

        assertLe(placedTokenInvariant.claimedAmount, placedTokenInvariant.boughtAmount);
        assertLe(placedTokenInvariant.claimedAmount, placedTokenInvariant.initialVolume);
    }

    // sumUsersAllowedAllocation calculated for the public sale round
    function assertSumUsersAllowedAllocationLeInitialVolume(address token) external view {
        LaunchpadHandler.PlacedTokenInvariants memory placedTokenInvariant = handler.getPlacedTokenInvariants(token);
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(token);

        assertLe(
            placedTokenInvariant.sumUsersAllowedAllocation,
            placedToken.initialVolumeForHighTiers + placedToken.initialVolumeForLowTiers
        );
    }

    function assertAddressForCollectedBalanceGteSendedAmount(address token) external view {
        LaunchpadHandler.PlacedTokenInvariants memory placedToken = handler.getPlacedTokenInvariants(token);

        assertGe(USDB.balanceOf(placedToken.addressForCollected), placedToken.sendedUSDB);
        assertGe(WETH.balanceOf(placedToken.addressForCollected), placedToken.sendedWETH);
    }

    function assertAddressBoughtAmountLeInitialVolume(address token) external view {
        LaunchpadHandler.PlacedTokenInvariants memory placedToken = handler.getPlacedTokenInvariants(token);

        assertLe(placedToken.boughtAmount, placedToken.initialVolume);
    }

    // function invariant_callSummary() public view {
    //     handler.callSummary();
    // }
}
