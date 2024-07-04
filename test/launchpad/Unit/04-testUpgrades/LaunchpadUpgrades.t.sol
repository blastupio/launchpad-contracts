// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, Types, MessageHashUtils, ECDSA, ERC20Mock} from "../../BaseLaunchpad.t.sol";
import {LaunchpadV2, BLPBalanceOracle} from "../../../../src/LaunchpadV2.sol";
import {LockedBLPStaking, LockedBLP} from "@blastup-token/LockedBLPStaking.sol";
import {BLPStaking} from "@blastup-token/BLPStaking.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "forge-std/console.sol";

contract LaunchpadV2Test is BaseLaunchpadTest {
    BLPBalanceOracle blpBalanceOracle;
    LockedBLP lockedBLP;
    LockedBLPStaking lockedBLPStaking;
    BLPStaking blpStaking;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        blpStaking = new BLPStaking(admin, address(blp), address(blp), address(points), admin);
        address lockedBLPStakingAddress = vm.computeCreateAddress(address(admin), vm.getNonce(admin) + 1);
        lockedBLP =
            new LockedBLP(lockedBLPStakingAddress, address(blp), address(points), admin, admin, 1000, 10, 2000, 10000);
        lockedBLPStaking = new LockedBLPStaking(admin, address(lockedBLP), address(blp), address(points), admin);
        blpBalanceOracle = new BLPBalanceOracle(admin, address(blpStaking), address(lockedBLPStaking));

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(launchpad)),
            address(new LaunchpadV2(address(WETH), address(USDB), address(oracle), address(staking))),
            abi.encodeCall(LaunchpadV2.initializeV2, (address(blpBalanceOracle)))
        );

        vm.stopPrank();
        assertEq(LaunchpadV2(address(launchpad)).blpBalanceOracle(), address(blpBalanceOracle));
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
        launchpad.register(id, tier, 0, bytes(""));
        Types.User memory userInfo = launchpad.userInfo(id, user);

        assertEq(uint8(userInfo.tier), uint8(tier));
        assertEq(userInfo.registered, true);
        assertEq(launchpad.userAllowedAllocation(id, user), 0);
        vm.stopPrank();

        vm.prank(user2);
        vm.expectRevert("BlastUP: you do not have enough BLP tokens for that tier");
        launchpad.register(id, tierDiamond, 0, bytes(""));
    }
}
