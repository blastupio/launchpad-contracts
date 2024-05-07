// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, Types} from "../../BaseLaunchpad.t.sol";

contract PlaceTokensTest is BaseLaunchpadTest {
    function test_placeTokens() public {
        uint256 initialVolume = 100 * 10 ** 18;
        uint256 initialVolumeForHighTiers = initialVolume * 60 / 100;
        uint256 initialVolumeForLowTiers = initialVolume * 20 / 100;
        uint256 volumeForYieldStakers = initialVolume * 20 / 100;
        address addressForCollected = address(2);
        uint256 price = 10 ** 18;
        uint256 vestingDuration = 60;
        uint8 tgePercent = 15;
        uint256 currentTokenId = 0;

        Types.PlacedToken memory input = Types.PlacedToken({
            price: price,
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            volumeForYieldStakers: volumeForYieldStakers,
            addressForCollected: addressForCollected,
            volume: initialVolume,
            registrationStart: block.timestamp + 1,
            registrationEnd: block.timestamp + 11,
            publicSaleStart: block.timestamp + 21,
            fcfsSaleStart: type(uint256).max - 3,
            saleEnd: type(uint256).max - 2,
            tgeStart: type(uint256).max - 1,
            vestingStart: type(uint256).max,
            vestingDuration: vestingDuration,
            tgePercent: tgePercent,
            lowTiersWeightsSum: 0,
            highTiersWeightsSum: 0,
            tokenDecimals: 18,
            approved: false,
            token: address(testToken)
        });

        vm.startPrank(admin);
        testToken.mint(admin, 100 * 10 ** 19);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input);

        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);

        assertEq(testToken.balanceOf(address(launchpad)), initialVolume);
        assertEq(placedToken.price, price);
        assertEq(placedToken.volumeForYieldStakers, volumeForYieldStakers);
        assertEq(placedToken.tokenDecimals, 18);

        input.initialVolumeForHighTiers = 0;
        input.initialVolumeForLowTiers = 0;
        input.volumeForYieldStakers = 0;

        vm.expectRevert("BlastUP: initial Volume must be > 0");

        launchpad.placeTokens(input);

        vm.stopPrank();
    }
}
