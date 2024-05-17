// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, Types, MessageHashUtils, ECDSA, ERC20Mock} from "../../BaseLaunchpad.t.sol";
import {LaunchpadV2, ILaunchpadV2, BLPStaking} from "../../../../src/LaunchpadV2.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/console.sol";

contract LaunchpadV2Test is BaseLaunchpadTest {
    BLPStaking blpStaking;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        blpStaking = new BLPStaking(address(blp), admin, address(points), admin);
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(launchpad)),
            address(new LaunchpadV2(address(WETH), address(USDB), address(oracle), address(staking))),
            abi.encodeCall(LaunchpadV2.initializeV2, (address(blpStaking)))
        );

        vm.stopPrank();
        assertEq(LaunchpadV2(address(launchpad)).blpStaking(), address(blpStaking));
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

    function test_registerV2() public placeTokens {
        uint256 amount = 10_000 * (10 ** 18); // BLP
        Types.UserTiers tier = Types.UserTiers.GOLD;
        Types.UserTiers tierDiamond = Types.UserTiers.DIAMOND;
        uint256 lockTime = 100;
        uint32 percent = 10 * 1e2;
        uint256 id = 0;

        uint256 preClaculatedReward = (amount * percent / 1e4) * lockTime / 365 days;

        blp.mint(user, amount);
        blp.mint(address(blpStaking), preClaculatedReward);

        vm.prank(admin);
        blpStaking.setLockTimeToPercent(lockTime, percent);

        vm.startPrank(user);
        blp.approve(address(blpStaking), amount);
        blpStaking.stake(amount, lockTime);
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert("Not implemented");
        ILaunchpadV2(address(launchpad)).register(id, tier, amount, bytes(""));
        vm.expectRevert("Not implemented");
        ILaunchpadV2(address(launchpad)).registerWithApprove(id, tier, amount, bytes(""), bytes(""));
        ILaunchpadV2(address(launchpad)).registerV2(id, tier);
        Types.User memory userInfo = launchpad.userInfo(id, user);

        assertEq(uint8(userInfo.tier), uint8(tier));
        assertEq(userInfo.registered, true);
        assertEq(launchpad.userAllowedAllocation(id, user), 0);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert("BlastUP: you do not have enough BLP tokens for that tier");
        ILaunchpadV2(address(launchpad)).registerV2(id, tierDiamond);
    }
}
