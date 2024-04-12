// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {BaseLaunchpadTest, Launchpad, ILaunchpad, MessageHashUtils, ECDSA} from "../../BaseLaunchpad.t.sol";
import "forge-std/console.sol";

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

    function getTierByAmount(uint256 _amount) internal view returns (ILaunchpad.UserTiers) {
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
        uint256 initialVolume,
        uint160 _addressForCollected,
        uint256 timeOfEndRegistration,
        uint256 price,
        uint256 tgePercent,
        uint256 volumeForHighTiers
    ) {
        initialVolume = bound(initialVolume, 1e21, 1e40);
        address addressForCollected = address(uint160(bound(_addressForCollected, 100, type(uint160).max)));

        price = bound(price, 1e3, 1e19);
        tgePercent = bound(tgePercent, 0, 100);
        volumeForHighTiers = bound(volumeForHighTiers, 50, 90);
        uint256 volumeForLowTiers = 95 - volumeForHighTiers;
        uint256 volumeForYieldStakers = 100 - volumeForLowTiers - volumeForHighTiers;

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
            tgePercent: uint8(tgePercent)
        });

        vm.startPrank(admin);
        testToken.mint(admin, initialVolume + 1);
        testToken.approve(address(launchpad), initialVolume + 1);
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

    modifier registerFuzz(uint256 amountOfTokens, uint256 amountOfTokens2) {
        amountOfTokens = bound(amountOfTokens, 2000, 19999);
        amountOfTokens2 = bound(amountOfTokens2, 20000, 1e30);

        ILaunchpad.UserTiers tier = getTierByAmount(amountOfTokens);
        ILaunchpad.UserTiers tier2 = getTierByAmount(amountOfTokens2);

        bytes memory signature = getSignature(user, amountOfTokens);

        vm.startPrank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();

        signature = getSignature(user2, amountOfTokens);

        vm.startPrank(user2);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);
        vm.stopPrank();

        signature = getSignature(user3, amountOfTokens2);

        vm.startPrank(user3);
        launchpad.register(address(testToken), tier2, amountOfTokens2, signature);
        vm.stopPrank();

        signature = getSignature(user4, amountOfTokens2);

        vm.startPrank(user4);
        launchpad.register(address(testToken), tier2, amountOfTokens2, signature);
        vm.stopPrank();

        vm.startPrank(admin);
        launchpad.endRegistration(address(testToken));
        vm.stopPrank();
        _;
    }

    modifier stake() {
        vm.startPrank(user5);

        USDB.mint(user5, 1e23);
        USDB.approve(address(staking), type(uint256).max);

        staking.stake(address(USDB), 5e22);

        vm.stopPrank();

        vm.startPrank(user6);

        WETH.mint(user6, 1e23);
        WETH.approve(address(staking), type(uint256).max);

        staking.stake(address(WETH), 5e20);

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
        USDB.mint(user, volume + 1);
        USDB.approve(address(launchpad), volume + 1);
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
        USDB.mint(user2, volume + 1);
        USDB.approve(address(launchpad), volume + 1);
        vm.expectRevert("BlastUP: You have not enough allocation");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user2);

        vm.stopPrank();
    }

    function test_RevertSetVestingStartTimestamp() public placeTokens register {
        vm.startPrank(admin);
        vm.warp(block.timestamp + 10);
        vm.expectRevert("BlastUP: invalid vesting start timestamp");
        launchpad.setVestingStartTimestamp(address(testToken), block.timestamp - 5);
        launchpad.setVestingStartTimestamp(address(testToken), block.timestamp + 600);
        vm.warp(block.timestamp + 601);
        vm.expectRevert("BlastUP: vesting already started");
        launchpad.setVestingStartTimestamp(address(testToken), block.timestamp + 10);
        vm.stopPrank();
    }

    function test_RevertSetTgeTimestamp() public placeTokens register {
        vm.startPrank(admin);
        vm.warp(block.timestamp + 10);
        vm.expectRevert("BlastUP: invalid tge timestamp");
        launchpad.setTgeTimestamp(address(testToken), block.timestamp - 5);
        launchpad.setTgeTimestamp(address(testToken), block.timestamp + 600);
        vm.warp(block.timestamp + 601);
        vm.expectRevert("BlastUP: tge already started");
        launchpad.setTgeTimestamp(address(testToken), block.timestamp + 10);
        vm.stopPrank();
    }

    function test_buyAndClaimFuzz(
        uint256 initialVolume,
        uint160 addressForCollected,
        uint256 timeOfEndRegistration,
        uint256 price,
        uint256 tgePercent,
        uint256 volumeForHighTiers,
        uint256 amountOfTokens,
        uint256 amountOfTokens2
    )
        public
        placeTokensFuzz(initialVolume, addressForCollected, timeOfEndRegistration, price, tgePercent, volumeForHighTiers)
        registerFuzz(amountOfTokens, amountOfTokens2)
        stake
    {
        uint256 endTimeOfTheCurrentRound = block.timestamp + 10;

        vm.startPrank(admin);
        launchpad.startPublicSale(address(testToken), endTimeOfTheCurrentRound);
        vm.stopPrank();

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        uint256 sumLowTiersUsersAllowedAllocation = launchpad.userAllowedAllocation(address(testToken), user)
            + launchpad.userAllowedAllocation(address(testToken), user2);

        assertApproxEqAbs(sumLowTiersUsersAllowedAllocation, placedToken.initialVolumeForLowTiers, 10);

        uint256 sumHighTiersUsersAllowedAllocation = launchpad.userAllowedAllocation(address(testToken), user3)
            + launchpad.userAllowedAllocation(address(testToken), user4);

        assertApproxEqAbs(sumHighTiersUsersAllowedAllocation, placedToken.initialVolumeForHighTiers, 10);

        vm.startPrank(user);
        ILaunchpad.User memory userInfoBefore = launchpad.userInfo(address(testToken), user);

        uint256 tokensAmount = launchpad.userAllowedAllocation(address(testToken), user) / 2;
        uint256 volume = tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals);

        USDB.mint(user, volume + 1e18);
        USDB.approve(address(launchpad), volume + 1);
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);

        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), user);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, tokensAmount / 100 + 1);
        vm.stopPrank();

        vm.startPrank(user3);
        userInfoBefore = launchpad.userInfo(address(testToken), user3);
        tokensAmount = launchpad.userAllowedAllocation(address(testToken), user) / 2;

        volume = tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals);
        volume /= 100; // usdbToEth
        WETH.mint(user3, volume + 1e18);
        WETH.approve(address(launchpad), volume + 1);
        launchpad.buyTokens(address(testToken), address(WETH), volume, user3);

        userInfo = launchpad.userInfo(address(testToken), user3);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, tokensAmount / 100 + 1);
        vm.stopPrank();

        vm.startPrank(user2);
        userInfoBefore = launchpad.userInfo(address(testToken), user2);

        tokensAmount = launchpad.userAllowedAllocation(address(testToken), user2) / 2;

        USDB.mint(user2, tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals) + 1e18);
        USDB.approve(address(launchpad), tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals) + 1e18);
        launchpad.buyTokensByQuantity(address(testToken), address(USDB), tokensAmount, user2);

        userInfo = launchpad.userInfo(address(testToken), user2);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, 1000);
        vm.stopPrank();

        vm.startPrank(user4);
        userInfoBefore = launchpad.userInfo(address(testToken), user4);

        tokensAmount = launchpad.userAllowedAllocation(address(testToken), user4) / 2;
        tokensAmount /= 100;
        WETH.mint(user4, tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals) + 1e18);
        WETH.approve(address(launchpad), tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals) + 1e18);
        launchpad.buyTokensByQuantity(address(testToken), address(WETH), tokensAmount, user4);

        userInfo = launchpad.userInfo(address(testToken), user4);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, 1000);
        vm.stopPrank();

        // TEST BUYING FROM STAKING

        vm.startPrank(user5);
        uint256 rewardAmount;
        (, uint256 reward) = staking.balanceAndRewards(address(USDB), user5);
        uint256 _max = reward > placedToken.volumeForYieldStakers ? placedToken.volumeForYieldStakers : reward;
        rewardAmount = bound(rewardAmount, placedToken.price / (10 ** placedToken.tokenDecimals) + 1, _max);
        staking.claimReward{gas: 1e18}(address(USDB), address(testToken), rewardAmount, false);

        userInfo = launchpad.userInfo(address(testToken), user5);
        assertGt(userInfo.boughtAmount, 0);
        vm.stopPrank();

        vm.startPrank(user6);
        rewardAmount = 0;
        (, reward) = staking.balanceAndRewards(address(WETH), user6);
        _max = reward > placedToken.volumeForYieldStakers ? placedToken.volumeForYieldStakers : reward;
        rewardAmount = bound(rewardAmount, placedToken.price / (10 ** placedToken.tokenDecimals) + 1, _max);
        staking.claimReward{gas: 1e18}(address(WETH), address(testToken), rewardAmount, false);

        userInfo = launchpad.userInfo(address(testToken), user6);
        assertGt(userInfo.boughtAmount, 0);
        vm.stopPrank();

        // START FCFS ROUND

        vm.startPrank(admin);
        launchpad.startFCFSSale(address(testToken), block.timestamp + 15);
        vm.stopPrank();

        vm.startPrank(user);
        volume = 100;
        USDB.approve(address(launchpad), volume + 1);
        vm.expectRevert();
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);
        vm.stopPrank();

        vm.startPrank(user2);
        volume = 100;
        USDB.approve(address(launchpad), volume + 1);
        vm.expectRevert();
        launchpad.buyTokensByQuantity(address(testToken), address(USDB), volume, user2);
        vm.stopPrank();

        // expect revert buying by staking yield
        vm.startPrank(user5);
        (, reward) = staking.balanceAndRewards(address(USDB), user5);
        _max = reward > placedToken.volumeForYieldStakers ? placedToken.volumeForYieldStakers : reward;
        rewardAmount = bound(rewardAmount, placedToken.price / (10 ** placedToken.tokenDecimals) + 1, _max);
        vm.expectRevert();
        staking.claimReward(address(USDB), address(testToken), rewardAmount, false);
        vm.stopPrank();

        vm.startPrank(user6);
        (, reward) = staking.balanceAndRewards(address(WETH), user6);
        _max = reward > placedToken.volumeForYieldStakers ? placedToken.volumeForYieldStakers : reward;
        rewardAmount = bound(rewardAmount, placedToken.price / (10 ** placedToken.tokenDecimals) + 1, _max);
        vm.expectRevert();
        staking.claimReward(address(WETH), address(testToken), rewardAmount, false);
        vm.stopPrank();

        vm.startPrank(user3);
        userInfoBefore = launchpad.userInfo(address(testToken), user3);
        tokensAmount = launchpad.userAllowedAllocation(address(testToken), user3) / 2;

        volume = tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals);
        volume /= 100;
        WETH.mint(user3, volume + 10);
        WETH.approve(address(launchpad), volume + 10);
        launchpad.buyTokens(address(testToken), address(WETH), volume, user3);

        userInfo = launchpad.userInfo(address(testToken), user3);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, tokensAmount / 100 + 1);
        vm.stopPrank();

        vm.startPrank(user4);
        userInfoBefore = launchpad.userInfo(address(testToken), user4);

        tokensAmount = launchpad.userAllowedAllocation(address(testToken), user4) / 2;
        USDB.mint(user4, tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals) + 10);
        USDB.approve(address(launchpad), tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals) + 1e18);
        launchpad.buyTokensByQuantity(address(testToken), address(USDB), tokensAmount, user4);

        userInfo = launchpad.userInfo(address(testToken), user4);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, tokensAmount / 100 + 1);
        vm.stopPrank();

        // endSale

        vm.startPrank(admin);
        launchpad.endSale(address(testToken));
        vm.expectRevert("BlastUp: invalid status");
        launchpad.endSale(address(testToken));

        assertEq(launchpad.getClaimableAmount(address(testToken), user), 0);

        // set tge timestamp +5 seconds from currentStateEnd
        userInfo = launchpad.userInfo(address(testToken), user);
        placedToken = launchpad.getPlacedToken(address(testToken));

        launchpad.setTgeTimestamp(address(testToken), placedToken.currentStateEnd + 5);
        assertEq(launchpad.getClaimableAmount(address(testToken), user), 0);
        vm.stopPrank();

        vm.warp(placedToken.currentStateEnd + 6);

        if (placedToken.tgePercent > 0) {
            assertEq(
                placedToken.tgePercent * userInfo.boughtAmount / 100,
                launchpad.getClaimableAmount(address(testToken), user)
            );
            // users claims their rewards
            vm.startPrank(user);

            uint256 claimableAmount = launchpad.getClaimableAmount(address(testToken), user);
            vm.expectEmit(true, true, true, true, address(launchpad));
            emit Launchpad.TokensClaimed(address(testToken), user);
            launchpad.claimTokens(address(testToken));

            userInfo = launchpad.userInfo(address(testToken), user);
            assertEq(launchpad.getClaimableAmount(address(testToken), user), 0);
            assertEq(userInfo.claimedAmount, claimableAmount);
            assertEq(testToken.balanceOf(user), claimableAmount);
            vm.stopPrank();

            vm.startPrank(user3);

            claimableAmount = launchpad.getClaimableAmount(address(testToken), user3);
            vm.expectEmit(true, true, true, true, address(launchpad));
            emit Launchpad.TokensClaimed(address(testToken), user3);
            launchpad.claimTokens(address(testToken));

            userInfo = launchpad.userInfo(address(testToken), user3);
            assertEq(launchpad.getClaimableAmount(address(testToken), user3), 0);
            assertEq(userInfo.claimedAmount, claimableAmount);
            assertEq(testToken.balanceOf(user3), claimableAmount);
            vm.stopPrank();

            vm.startPrank(user5);

            claimableAmount = launchpad.getClaimableAmount(address(testToken), user5);
            if (claimableAmount > 0) {
                vm.expectEmit(true, true, true, true, address(launchpad));
                emit Launchpad.TokensClaimed(address(testToken), user5);
                launchpad.claimTokens(address(testToken));

                userInfo = launchpad.userInfo(address(testToken), user5);
                assertEq(launchpad.getClaimableAmount(address(testToken), user5), 0);
                assertEq(userInfo.claimedAmount, claimableAmount);
                assertEq(testToken.balanceOf(user5), claimableAmount);
            }
            vm.stopPrank();
        }
        vm.startPrank(admin);
        // set vesting start timestamp +5 seconds from now
        launchpad.setVestingStartTimestamp(address(testToken), block.timestamp + 5);
        vm.stopPrank();

        placedToken = launchpad.getPlacedToken(address(testToken));

        uint256 user2_claimableAmountBeforeVesting = launchpad.getClaimableAmount(address(testToken), user2);
        uint256 user4_claimableAmountBeforeVesting = launchpad.getClaimableAmount(address(testToken), user4);
        uint256 user6_claimableAmountBeforeVesting = launchpad.getClaimableAmount(address(testToken), user6);
        ILaunchpad.User memory user2Info = launchpad.userInfo(address(testToken), user2);
        ILaunchpad.User memory user4Info = launchpad.userInfo(address(testToken), user4);
        ILaunchpad.User memory user6Info = launchpad.userInfo(address(testToken), user6);

        if (placedToken.tgePercent < 100) {
            vm.warp(placedToken.vestingStartTimestamp + placedToken.vestingDuration / 2);

            assertApproxEqAbs(
                launchpad.getClaimableAmount(address(testToken), user2) - user2_claimableAmountBeforeVesting,
                (user2Info.boughtAmount - user2_claimableAmountBeforeVesting) / 2,
                10
            );
            assertApproxEqAbs(
                launchpad.getClaimableAmount(address(testToken), user4) - user4_claimableAmountBeforeVesting,
                (user4Info.boughtAmount - user4_claimableAmountBeforeVesting) / 2,
                10
            );
            assertApproxEqAbs(
                launchpad.getClaimableAmount(address(testToken), user6) - user6_claimableAmountBeforeVesting,
                (user6Info.boughtAmount - user6_claimableAmountBeforeVesting) / 2,
                10
            );
        }

        vm.warp(placedToken.vestingStartTimestamp + placedToken.vestingDuration + 1);

        vm.startPrank(user2);
        launchpad.claimTokens(address(testToken));
        assertEq(testToken.balanceOf(user2), user2Info.boughtAmount);
        vm.stopPrank();

        vm.startPrank(user4);
        launchpad.claimTokens(address(testToken));
        assertEq(testToken.balanceOf(user2), user2Info.boughtAmount);
        vm.stopPrank();

        vm.startPrank(user6);
        launchpad.claimTokens(address(testToken));
        assertEq(testToken.balanceOf(user2), user2Info.boughtAmount);
        vm.stopPrank();
    }
}
