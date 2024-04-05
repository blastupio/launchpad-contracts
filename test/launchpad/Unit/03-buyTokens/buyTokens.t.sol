// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, ILaunchpad, MessageHashUtils, ECDSA} from "../../BaseLaunchpad.t.sol";

contract BuyTokensTest is BaseLaunchpadTest {
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    function getSignature(address _user, uint256 _amountOfTokens) internal returns (bytes memory) {
        vm.startPrank(admin);
        bytes32 digest = keccak256(abi.encodePacked(_user, _amountOfTokens, address(launchpad), block.chainid))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        return signature;
    }

    function getTierByAmount(uint256 _amount) internal returns (ILaunchpad.UserTiers) {
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.DIAMOND)) return ILaunchpad.UserTiers.DIAMOND;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.PLATINUM)) return ILaunchpad.UserTiers.PLATINUM;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.TITANIUM)) return ILaunchpad.UserTiers.TITANIUM;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.GOLD)) return ILaunchpad.UserTiers.GOLD;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.SILVER)) return ILaunchpad.UserTiers.SILVER;
        return ILaunchpad.UserTiers.BRONZE;
    }

    modifier placeTokens() {
        uint256 nowTimestamp = block.timestamp;
        uint256 initialVolume = 100 * 10 ** 18;
        uint256 initialVolumeForHighTiers = initialVolume * 60 / 100;
        uint256 initialVolumeForLowTiers = initialVolume * 20 / 100;
        uint256 initialVolumeForYieldStakers = initialVolume * 20 / 100;
        address addressForCollected = address(2);
        uint256 timeOfEndRegistration = nowTimestamp + 600;
        uint256 price = 10 ** 18;
        uint256 vestingDuration = 60;
        uint8 tgePercent = 15;

        ILaunchpad.PlaceTokensInput memory input = ILaunchpad.PlaceTokensInput({
            price: price,
            token: address(testToken),
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            initialVolumeForYieldStakers: initialVolumeForYieldStakers,
            timeOfEndRegistration: timeOfEndRegistration,
            addressForCollected: addressForCollected,
            vestingDuration: vestingDuration,
            tgePercent: tgePercent
        });

        vm.startPrank(admin);
        testToken.mint(admin, 100 * 10 ** 19);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input);
        vm.stopPrank();
        _;
    }

    modifier placeTokensFuzz(
        uint128 initialVolume,
        address addressForCollected,
        uint256 timeOfEndRegistration,
        uint256 price,
        uint8 tgePercent
    ) {
        vm.assume(initialVolume > 1e16);
        vm.assume(addressForCollected > address(20));
        vm.assume(timeOfEndRegistration > 1);
        vm.assume(price > 1e3);

        uint256 initialVolume = uint256(initialVolume);

        uint256 nowTimestamp = block.timestamp;
        uint256 initialVolumeForHighTiers = initialVolume * 60 / 100;
        uint256 initialVolumeForLowTiers = initialVolume * 20 / 100;
        uint256 initialVolumeForYieldStakers = initialVolume * 20 / 100;
        uint256 vestingDuration = 60;

        ILaunchpad.PlaceTokensInput memory input = ILaunchpad.PlaceTokensInput({
            price: price,
            token: address(testToken),
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            initialVolumeForYieldStakers: initialVolumeForYieldStakers,
            timeOfEndRegistration: timeOfEndRegistration,
            addressForCollected: addressForCollected,
            vestingDuration: vestingDuration,
            tgePercent: tgePercent
        });

        vm.startPrank(admin);
        testToken.mint(admin, initialVolume + 1);
        testToken.approve(address(launchpad), type(uint256).max);
        launchpad.placeTokens(input);
        vm.stopPrank();
        _;
    }

    modifier register() {
        uint256 amountOfTokens = 2000;
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.BRONZE;
        bytes memory signature = getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();

        vm.startPrank(admin);
        launchpad.endRegistration(address(testToken));
        vm.stopPrank();
        _;
    }

    modifier registerFuzz(uint16 amountOfTokens, uint64 amountOfTokens2) {
        vm.assume(amountOfTokens >= 2000);
        vm.assume(amountOfTokens2 >= 2000);

        uint256 amountOfTokens = uint256(amountOfTokens);
        uint256 amountOfTokens2 = uint256(amountOfTokens2);

        ILaunchpad.UserTiers tier = getTierByAmount(amountOfTokens);
        ILaunchpad.UserTiers tier2 = getTierByAmount(amountOfTokens);

        bytes memory signature = getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();

        signature = getSignature(user2, amountOfTokens);

        vm.startPrank(user2);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();

        signature = getSignature(user3, amountOfTokens);

        vm.startPrank(user3);
        launchpad.register(address(testToken), tier2, amountOfTokens2, signature);
        vm.stopPrank();

        signature = getSignature(user4, amountOfTokens);

        vm.startPrank(user4);
        launchpad.register(address(testToken), tier2, amountOfTokens2, signature);
        vm.stopPrank();

        vm.startPrank(admin);
        launchpad.endRegistration(address(testToken));
        vm.stopPrank();
        _;
    }

    function test_RevertBuyTokens_InvalidStatus() public placeTokens register {
        uint256 volume = 1e18;

        vm.startPrank(user);

        vm.expectRevert("BlastUP: invalid status");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);

        vm.stopPrank();
    }

    function test_RevertBuyTokens_RoundEnded() public placeTokens register {
        uint256 volume = 1e18;

        vm.startPrank(admin);
        launchpad.startPublicSale(address(testToken), block.timestamp + 100);
        vm.stopPrank();

        vm.warp(block.timestamp + 800);

        vm.startPrank(user);

        vm.expectRevert("BlastUP: round is ended");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);

        vm.stopPrank();
    }

    function test_RevertBuyTokens_VolumeIsZero() public placeTokens register {
        uint256 volume = 0;

        vm.startPrank(admin);
        launchpad.startPublicSale(address(testToken), block.timestamp + 100);
        vm.stopPrank();

        vm.startPrank(user);

        vm.expectRevert("BlastUP: volume must be greater than 0");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);

        vm.stopPrank();
    }

    function test_RevertBuyTokens_ReceiverMustBeTheSender() public placeTokens register {
        uint256 volume = 100e18;

        vm.startPrank(admin);
        launchpad.startPublicSale(address(testToken), block.timestamp + 100);
        vm.stopPrank();

        vm.startPrank(user);

        vm.expectRevert("BlastUP: the receiver must be the sender");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user2);

        vm.stopPrank();
    }

    function test_RevertBuyTokens_NotEnoughAllocation() public placeTokens register {
        uint256 volume = 100e18;

        vm.startPrank(admin);
        launchpad.startPublicSale(address(testToken), block.timestamp + 100);
        vm.stopPrank();

        vm.startPrank(user2);

        vm.expectRevert("BlastUP: You have not enough allocation");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user2);

        vm.stopPrank();
    }

    // function test_BuyTokens_Fuzz(
    //     uint128 initialVolume,
    //     address addressForCollected,
    //     uint256 timeOfEndRegistration,
    //     uint256 price,
    //     uint8 tgePercent,
    //     uint16 amountOfTokens,
    //     uint64 amountOfTokens2,
    //     address paymentContract
    // )
    //     public
    //     placeTokensFuzz(initialVolume, addressForCollected, timeOfEndRegistration, price, tgePercent)
    //     registerFuzz(amountOfTokens, amountOfTokens2)
    // {

    // }
}
