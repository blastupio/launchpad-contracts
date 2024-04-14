// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, ILaunchpad, MessageHashUtils, ECDSA} from "../../BaseLaunchpad.t.sol";

contract PlaceTokensRegistrationTest is BaseLaunchpadTest {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    function _getSignature(address _user, uint256 _amountOfTokens) internal returns (bytes memory) {
        vm.startPrank(admin);
        bytes32 digest = keccak256(abi.encodePacked(_user, _amountOfTokens, address(launchpad), block.chainid))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        return signature;
    }

    modifier placeTokens() {
        uint256 initialVolume = 100 * 10 ** 18;
        uint256 initialVolumeForHighTiers = initialVolume * 60 / 100;
        uint256 initialVolumeForLowTiers = initialVolume * 20 / 100;
        uint256 volumeForYieldStakers = initialVolume * 20 / 100;
        address addressForCollected = address(2);
        uint256 price = 10 ** 18;
        uint256 vestingDuration = 60;
        uint8 tgePercent = 15;

        ILaunchpad.PlacedToken memory input = ILaunchpad.PlacedToken({
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
            initialized: true,
            lowTiersWeightsSum: 0,
            highTiersWeightsSum: 0,
            tokenDecimals: 18
        });

        vm.startPrank(admin);
        testToken.mint(admin, 100 * 10 ** 19);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input, address(testToken));
        vm.stopPrank();
        vm.warp(input.registrationStart);
        _;
    }

    modifier placeTokensFuzz(
        uint256 initialVolume,
        address addressForCollected,
        uint256 timeOfEndRegistration,
        uint256 price,
        uint8 tgePercent
    ) {
        vm.assume(addressForCollected > address(20));
        vm.assume(timeOfEndRegistration > (block.timestamp + 2) && timeOfEndRegistration < 1e40);
        vm.assume(price > 1e3);
        vm.assume(tgePercent <= 100);

        initialVolume = bound(initialVolume, 1e18, 1e37);

        uint256 initialVolumeForHighTiers = initialVolume * 60;
        uint256 initialVolumeForLowTiers = initialVolume * 20;
        uint256 volumeForYieldStakers = initialVolume * 20;
        uint256 vestingDuration = 60;
        initialVolume *= 100;

        ILaunchpad.PlacedToken memory input = ILaunchpad.PlacedToken({
            price: price,
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            volumeForYieldStakers: volumeForYieldStakers,
            addressForCollected: addressForCollected,
            volume: initialVolume,
            registrationStart: block.timestamp + 1,
            registrationEnd: timeOfEndRegistration,
            publicSaleStart: timeOfEndRegistration + 21,
            fcfsSaleStart: type(uint256).max - 3,
            saleEnd: type(uint256).max - 2,
            tgeStart: type(uint256).max - 1,
            vestingStart: type(uint256).max,
            vestingDuration: vestingDuration,
            tgePercent: tgePercent,
            initialized: true,
            lowTiersWeightsSum: 0,
            highTiersWeightsSum: 0,
            tokenDecimals: 18
        });

        vm.startPrank(admin);
        testToken.mint(admin, initialVolume + 1);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input, address(testToken));
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
        _;
    }

    function test_RevertRegistration_InvalidSignature() public placeTokens {
        uint256 amountOfTokens = 2000; // BLP
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.BRONZE;

        vm.startPrank(admin);

        bytes32 digest = keccak256(abi.encodePacked(user, amountOfTokens - 1, address(launchpad), block.chainid))
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(user);

        vm.expectRevert("BlastUP: Invalid signature");
        launchpad.register(address(testToken), tier, amountOfTokens, signature);

        vm.stopPrank();
    }

    function test_RevertRegistration_InvalidStatus() public placeTokens {
        uint256 amountOfTokens = 2000; // BLP
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.BRONZE;

        vm.warp(block.timestamp + 700);

        bytes memory signature = _getSignature(user, amountOfTokens);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("BlastUP: invalid status");
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function test_RevertRegistration_InvalidTier() public placeTokens {
        uint256 amountOfTokens = 2000; // BLP
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.GOLD;

        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.startPrank(user);
        vm.expectRevert("BlastUP: you do not have enough BLP tokens for that tier");
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function test_Register() public placeTokens {
        uint256 amountOfTokens = 2000; // BLP
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.BRONZE;

        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), user);

        assertEq(uint8(userInfo.tier), uint8(tier));
        assertEq(userInfo.registered, true);
        assertEq(launchpad.userAllowedAllocation(address(testToken), user), 0);
        vm.stopPrank();
    }

    function test_RevertRegistration_AlreadyRegisteredUser() public placeTokens {
        uint256 amountOfTokens = 2000; // BLP
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.BRONZE;

        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.expectRevert("BlastUP: you are already registered");
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function _checkRegisterUser(address _user, uint256 _amountOfTokens, ILaunchpad.UserTiers tier) internal {
        bytes memory signature = _getSignature(_user, _amountOfTokens);
        vm.prank(_user);
        launchpad.register(address(testToken), tier, _amountOfTokens, signature);
        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), _user);
        assertEq(uint8(userInfo.tier), uint8(tier));
        assertTrue(userInfo.registered);
    }

    function test_Register_Fuzz(
        uint128 initialVolume,
        address addressForCollected,
        uint256 timeOfEndRegistration,
        uint256 price,
        uint8 tgePercent,
        uint256 amountOfTokens,
        uint256 amountOfTokens1,
        uint256 amountOfTokens2,
        uint256 amountOfTokens3,
        uint256 amountOfTokens4,
        uint256 amountOfTokens5,
        uint256 amountOfTokens6
    ) public placeTokensFuzz(initialVolume, addressForCollected, timeOfEndRegistration, price, tgePercent) {
        ILaunchpad.UserTiers tier1 = ILaunchpad.UserTiers.BRONZE;
        ILaunchpad.UserTiers tier2 = ILaunchpad.UserTiers.SILVER;
        ILaunchpad.UserTiers tier3 = ILaunchpad.UserTiers.GOLD;
        ILaunchpad.UserTiers tier4 = ILaunchpad.UserTiers.TITANIUM;
        ILaunchpad.UserTiers tier5 = ILaunchpad.UserTiers.PLATINUM;
        ILaunchpad.UserTiers tier6 = ILaunchpad.UserTiers.DIAMOND;

        amountOfTokens = bound(amountOfTokens, 0, launchpad.minAmountForTier(tier1) - 1);
        amountOfTokens1 =
            bound(amountOfTokens1, launchpad.minAmountForTier(tier1), launchpad.minAmountForTier(tier2) - 1);
        amountOfTokens2 =
            bound(amountOfTokens2, launchpad.minAmountForTier(tier2), launchpad.minAmountForTier(tier3) - 1);
        amountOfTokens3 =
            bound(amountOfTokens3, launchpad.minAmountForTier(tier3), launchpad.minAmountForTier(tier4) - 1);
        amountOfTokens4 =
            bound(amountOfTokens4, launchpad.minAmountForTier(tier4), launchpad.minAmountForTier(tier5) - 1);
        amountOfTokens5 =
            bound(amountOfTokens5, launchpad.minAmountForTier(tier5), launchpad.minAmountForTier(tier6) - 1);
        amountOfTokens6 = bound(amountOfTokens6, launchpad.minAmountForTier(tier6), 1e36);

        bytes memory signature = _getSignature(user, amountOfTokens);
        vm.startPrank(user);
        vm.expectRevert();
        launchpad.register(address(testToken), tier1, amountOfTokens, signature);
        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), user);
        assertTrue(!userInfo.registered);
        vm.stopPrank();

        _checkRegisterUser(user, amountOfTokens1, tier1);
        _checkRegisterUser(user2, amountOfTokens2, tier2);
        _checkRegisterUser(user3, amountOfTokens3, tier3);
        _checkRegisterUser(user4, amountOfTokens4, tier4);
        _checkRegisterUser(user5, amountOfTokens5, tier5);
        _checkRegisterUser(user6, amountOfTokens6, tier6);
    }
}
