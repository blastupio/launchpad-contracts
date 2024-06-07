// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, Types, MessageHashUtils, ECDSA} from "../../BaseLaunchpad.t.sol";

contract PlaceTokensRegistrationTest is BaseLaunchpadTest {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    function _getSignature(address _user, uint256 _amountOfTokens) internal returns (bytes memory signature) {
        vm.startPrank(admin);
        bytes32 digest = keccak256(abi.encodePacked(_user, _amountOfTokens, address(launchpad), block.chainid))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
    }

    function _getApproveSignature(address _user, uint256 _id) internal returns (bytes memory signature) {
        vm.startPrank(admin);
        bytes32 digest =
            keccak256(abi.encodePacked(_user, _id, address(launchpad), block.chainid)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
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
            token: address(testToken),
            fcfsOpened: false,
            fcfsRequiredTier: Types.UserTiers.TITANIUM
        });

        vm.startPrank(admin);
        testToken.mint(admin, 100 * 10 ** 19);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input);
        vm.stopPrank();
        vm.warp(input.registrationStart);
        _;
    }

    modifier placeTokensWithApprove() {
        uint256 initialVolume = 100 * 10 ** 18;
        uint256 initialVolumeForHighTiers = initialVolume * 60 / 100;
        uint256 initialVolumeForLowTiers = initialVolume * 20 / 100;
        uint256 volumeForYieldStakers = initialVolume * 20 / 100;
        address addressForCollected = address(2);
        uint256 price = 10 ** 18;
        uint256 vestingDuration = 60;
        uint8 tgePercent = 15;

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
            approved: true,
            token: address(testToken),
            fcfsOpened: false,
            fcfsRequiredTier: Types.UserTiers.TITANIUM
        });

        vm.startPrank(admin);
        testToken.mint(admin, 100 * 10 ** 19);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input);
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

        Types.PlacedToken memory input = Types.PlacedToken({
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
            lowTiersWeightsSum: 0,
            highTiersWeightsSum: 0,
            tokenDecimals: 18,
            approved: false,
            token: address(testToken),
            fcfsOpened: false,
            fcfsRequiredTier: Types.UserTiers.TITANIUM
        });

        vm.startPrank(admin);
        testToken.mint(admin, initialVolume + 1);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
        _;
    }

    function test_timestampSetters() public placeTokens {
        uint256 id = 0;

        vm.startPrank(user);
        vm.expectRevert();
        launchpad.setRegistrationStart(id, block.timestamp + 10);

        vm.expectRevert();
        launchpad.setRegistrationEnd(id, block.timestamp + 100);

        vm.expectRevert();
        launchpad.setPublicSaleStart(id, block.timestamp + 100);

        vm.expectRevert();
        launchpad.setFCFSSaleStart(id, block.timestamp + 100);

        vm.expectRevert();
        launchpad.setSaleEnd(id, block.timestamp + 100);

        vm.expectRevert();
        launchpad.setVestingStart(id, block.timestamp + 100);
        vm.stopPrank();

        vm.startPrank(admin);

        launchpad.setRegistrationStart(id, block.timestamp + 10);
        launchpad.setRegistrationEnd(id, block.timestamp + 101);
        launchpad.setPublicSaleStart(id, block.timestamp + 102);
        launchpad.setFCFSSaleStart(id, block.timestamp + 103);
        launchpad.setSaleEnd(id, block.timestamp + 104);
        launchpad.setVestingStart(id, block.timestamp + 105);

        vm.stopPrank();
    }

    function test_weightsSetters() public placeTokens {
        uint256[6] memory weights = [uint256(10), 25, 65, 10, 25, 65];
        uint256[6] memory amounts = [
            uint256(2_000 * (10 ** 18)),
            5_000 * (10 ** 18),
            10_000 * (10 ** 18),
            20_000 * (10 ** 18),
            50_000 * (10 ** 18),
            100_000 * (10 ** 18)
        ];

        vm.startPrank(user);
        vm.expectRevert();
        launchpad.setWeightsForTiers(weights);

        vm.expectRevert();
        launchpad.setMinAmountsForTiers(amounts);
        vm.stopPrank();

        vm.startPrank(admin);
        launchpad.setWeightsForTiers(weights);
        launchpad.setMinAmountsForTiers(amounts);

        launchpad.setOperator(user);
        vm.stopPrank();

        vm.startPrank(user);
        launchpad.setWeightsForTiers(weights);
        launchpad.setMinAmountsForTiers(amounts);
        vm.stopPrank();
    }

    function test_signerSetter() public placeTokens {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.BRONZE;
        uint256 id = 0;

        vm.startPrank(user);
        bytes32 digest = keccak256(abi.encodePacked(user, amountOfTokens, address(launchpad), block.chainid))
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert("BlastUP: Invalid signature");
        launchpad.register(id, tier, amountOfTokens, signature);
        vm.stopPrank();

        vm.startPrank(admin);
        launchpad.setSigner(signer);
        vm.stopPrank();

        vm.prank(user);
        launchpad.register(id, tier, amountOfTokens, signature);
    }

    function test_RevertRegistration_InvalidSignature() public placeTokens {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.BRONZE;
        uint256 id = 0;

        vm.startPrank(admin);

        bytes32 digest = keccak256(abi.encodePacked(user, amountOfTokens - 1, address(launchpad), block.chainid))
            .toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();

        vm.startPrank(user);

        vm.expectRevert("BlastUP: Invalid signature");
        launchpad.register(id, tier, amountOfTokens, signature);

        vm.stopPrank();
    }

    function test_RevertRegistration_InvalidStatus() public placeTokens {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.BRONZE;
        uint256 id = 0;

        vm.warp(block.timestamp + 700);

        bytes memory signature = _getSignature(user, amountOfTokens);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("BlastUP: invalid status");
        launchpad.register(id, tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function test_RevertRegistration_InvalidTier() public placeTokens {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.GOLD;
        uint256 id = 0;

        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.startPrank(user);
        vm.expectRevert("BlastUP: you do not have enough BLP tokens for that tier");
        launchpad.register(id, tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function test_Register() public placeTokens {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.BRONZE;
        uint256 id = 0;

        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(id, tier, amountOfTokens, signature);
        Types.User memory userInfo = launchpad.userInfo(id, user);

        assertEq(uint8(userInfo.tier), uint8(tier));
        assertEq(userInfo.registered, true);
        assertEq(launchpad.userAllowedAllocation(id, user), 0);
        vm.stopPrank();
    }

    function test_RegisterWithApprove() public placeTokensWithApprove {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.BRONZE;
        uint256 id = 0;

        bytes memory signature = _getSignature(user, amountOfTokens);
        bytes memory approveSignature = _getApproveSignature(user, id);

        vm.startPrank(user);
        vm.expectRevert("BlastUP: you need to use register with approve function");
        launchpad.register(id, tier, amountOfTokens, signature);
        launchpad.registerWithApprove(id, tier, amountOfTokens, signature, approveSignature);
        Types.User memory userInfo = launchpad.userInfo(id, user);

        assertEq(uint8(userInfo.tier), uint8(tier));
        assertEq(userInfo.registered, true);
        assertEq(launchpad.userAllowedAllocation(id, user), 0);
        vm.stopPrank();
    }

    function test_RevertRegistration_AlreadyRegisteredUser() public placeTokens {
        uint256 amountOfTokens = 2_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.BRONZE;
        uint256 id = 0;

        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(id, tier, amountOfTokens, signature);
        vm.expectRevert("BlastUP: you are already registered");
        launchpad.register(id, tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function _checkRegisterUser(address _user, uint256 _amountOfTokens, Types.UserTiers tier) internal {
        bytes memory signature = _getSignature(_user, _amountOfTokens);
        uint256 id = 0;
        vm.prank(_user);
        launchpad.register(id, tier, _amountOfTokens, signature);
        Types.User memory userInfo = launchpad.userInfo(id, _user);
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
        uint256 id = 0;
        Types.UserTiers tier1 = Types.UserTiers.BRONZE;
        Types.UserTiers tier2 = Types.UserTiers.SILVER;
        Types.UserTiers tier3 = Types.UserTiers.GOLD;
        Types.UserTiers tier4 = Types.UserTiers.TITANIUM;
        Types.UserTiers tier5 = Types.UserTiers.PLATINUM;
        Types.UserTiers tier6 = Types.UserTiers.DIAMOND;

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
        launchpad.register(id, tier1, amountOfTokens, signature);
        Types.User memory userInfo = launchpad.userInfo(id, user);
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
