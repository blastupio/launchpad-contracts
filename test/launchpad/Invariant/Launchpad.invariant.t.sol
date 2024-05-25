// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseLaunchpadTest, Launchpad, Types} from "../BaseLaunchpad.t.sol";
import {LaunchpadHandler} from "./Handlers/LaunchpadHandler.sol";

contract LaunchpadInvariant is BaseLaunchpadTest {
    LaunchpadHandler handler;

    function setUp() public override {
        super.setUp();
        handler = new LaunchpadHandler(launchpad, address(USDB), address(WETH), adminPrivateKey);

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = LaunchpadHandler.buyTokens.selector;
        selectors[1] = LaunchpadHandler.claimTokens.selector;
        selectors[2] = LaunchpadHandler.claimRemainders.selector;
        selectors[3] = LaunchpadHandler.placeTokens.selector;
        selectors[4] = LaunchpadHandler.setVestingStart.selector;
        selectors[5] = LaunchpadHandler.setTgeStart.selector;
        selectors[6] = LaunchpadHandler.setSaleEnd.selector;
        selectors[7] = LaunchpadHandler.setFCFSSaleStart.selector;
        selectors[8] = LaunchpadHandler.warp.selector;

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

    function assertClaimedAmountLeBoughtAmount(uint256 id) public view {
        LaunchpadHandler.PlacedTokenInvariants memory placedTokenInvariant = handler.getPlacedTokenInvariants(id);

        assertLe(placedTokenInvariant.claimedAmount, placedTokenInvariant.boughtAmount);
        assertLe(placedTokenInvariant.claimedAmount, placedTokenInvariant.initialVolume);
    }

    // sumUsersAllowedAllocation calculated for the public sale round
    function assertSumUsersAllowedAllocationLeInitialVolume(uint256 id) external view {
        LaunchpadHandler.PlacedTokenInvariants memory placedTokenInvariant = handler.getPlacedTokenInvariants(id);
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(id);

        assertLe(
            placedTokenInvariant.sumUsersAllowedAllocation,
            placedToken.initialVolumeForHighTiers + placedToken.initialVolumeForLowTiers
        );
    }

    function assertAddressForCollectedBalanceGteSendedAmount(uint256 id) external view {
        LaunchpadHandler.PlacedTokenInvariants memory placedToken = handler.getPlacedTokenInvariants(id);

        assertGe(USDB.balanceOf(placedToken.addressForCollected), placedToken.sendedUSDB);
        assertGe(WETH.balanceOf(placedToken.addressForCollected), placedToken.sendedWETH);
    }

    function assertAddressBoughtAmountLeInitialVolume(uint256 id) external view {
        LaunchpadHandler.PlacedTokenInvariants memory placedToken = handler.getPlacedTokenInvariants(id);

        assertLe(placedToken.boughtAmount, placedToken.initialVolume);
    }
}
