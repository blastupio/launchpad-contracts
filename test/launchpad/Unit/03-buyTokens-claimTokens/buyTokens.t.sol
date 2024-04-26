// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25;

import {
    BaseLaunchpadTest,
    Launchpad,
    ILaunchpad,
    MessageHashUtils,
    ECDSA,
    ERC20Mock,
    ERC20RebasingMock
} from "../../BaseLaunchpad.t.sol";
import "forge-std/console.sol";

contract BuyTokensTest is BaseLaunchpadTest {
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

    function _getTierByAmount(uint256 _amount) internal view returns (ILaunchpad.UserTiers) {
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.DIAMOND)) return ILaunchpad.UserTiers.DIAMOND;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.PLATINUM)) return ILaunchpad.UserTiers.PLATINUM;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.TITANIUM)) return ILaunchpad.UserTiers.TITANIUM;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.GOLD)) return ILaunchpad.UserTiers.GOLD;
        if (_amount >= launchpad.minAmountForTier(ILaunchpad.UserTiers.SILVER)) return ILaunchpad.UserTiers.SILVER;
        return ILaunchpad.UserTiers.BRONZE;
    }

    function _usersClaimRewardsTge(address _user) internal {
        uint256 claimableAmount = launchpad.getClaimableAmount(address(testToken), _user);
        if (claimableAmount > 0) {
            vm.startPrank(_user);
            vm.expectEmit(true, true, true, true, address(launchpad));
            emit Launchpad.TokensClaimed(address(testToken), _user);
            launchpad.claimTokens(address(testToken));

            ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), _user);
            assertEq(launchpad.getClaimableAmount(address(testToken), _user), 0);
            assertEq(userInfo.claimedAmount, claimableAmount);
            assertEq(testToken.balanceOf(_user), claimableAmount);
            vm.stopPrank();
        }
    }

    function _checkClaimableAmountDuringTheVestingPeriod(address _user, uint256 user_claimableAmountBeforeVesting)
        internal
        view
    {
        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), _user);
        assertApproxEqAbs(
            launchpad.getClaimableAmount(address(testToken), _user) - user_claimableAmountBeforeVesting,
            (userInfo.boughtAmount - user_claimableAmountBeforeVesting) / 2,
            10
        );
    }

    function _checkClaimableAmountAfterTheVestingPeriod(address _user) internal {
        if (launchpad.getClaimableAmount(address(testToken), _user) > 0) {
            ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), _user);
            vm.prank(_user);
            launchpad.claimTokens(address(testToken));
            assertEq(testToken.balanceOf(_user), userInfo.boughtAmount);
        }
    }

    function _buyFromStaking(ILaunchpad.PlacedToken memory placedToken, address _user, address paymentContract)
        internal
    {
        ERC20RebasingMock(paymentContract).addRewards(address(staking), 1e18);
        uint256 rewardAmount;
        (, uint256 reward) = staking.balanceAndRewards(paymentContract, _user);
        uint256 _max = reward > placedToken.volumeForYieldStakers ? placedToken.volumeForYieldStakers : reward;
        rewardAmount = bound(rewardAmount, placedToken.price / (10 ** placedToken.tokenDecimals) + 1, _max);
        vm.prank(_user);
        staking.claimReward{gas: 1e18}(paymentContract, address(testToken), rewardAmount, false);

        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), _user);
        assertGt(userInfo.boughtAmount, 0);
    }

    function _buyTokens(ILaunchpad.PlacedToken memory placedToken, address _user, address paymentContract) internal {
        vm.startPrank(_user);
        ILaunchpad.User memory userInfoBefore = launchpad.userInfo(address(testToken), _user);

        uint256 tokensAmount = launchpad.userAllowedAllocation(address(testToken), _user) / 2;
        uint256 volume = tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals);
        volume /= paymentContract == address(WETH) ? 100 : 1;

        ERC20Mock(paymentContract).mint(_user, volume + 1e18);
        ERC20Mock(paymentContract).approve(address(launchpad), volume + 1);
        launchpad.buyTokens(address(testToken), paymentContract, volume, _user);

        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), _user);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, tokensAmount / 100 + 1);
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
        uint160 _addressForCollected,
        uint256 timeOfEndRegistration,
        uint256 price,
        uint256 tgePercent,
        uint256 volumeForHighTiers
    ) {
        initialVolume = bound(initialVolume, 1e18, 1e37);
        address addressForCollected = address(uint160(bound(_addressForCollected, 100, type(uint160).max)));

        price = bound(price, 1e3, 1e19);
        tgePercent = bound(tgePercent, 0, 100);
        timeOfEndRegistration = bound(timeOfEndRegistration, 10, 1e20);

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
            tgePercent: uint8(tgePercent),
            initialized: true,
            lowTiersWeightsSum: 0,
            highTiersWeightsSum: 0,
            tokenDecimals: 18
        });

        vm.startPrank(admin);
        testToken.mint(admin, initialVolume + 1);
        testToken.approve(address(launchpad), initialVolume + 1);
        launchpad.placeTokens(input, address(testToken));
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
        _;
    }

    modifier register() {
        uint256 amountOfTokens = 2000;
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers.BRONZE;
        bytes memory signature = _getSignature(user, amountOfTokens);

        vm.prank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.registrationEnd);
        _;
    }

    modifier registerFuzz(uint256 amountOfTokens, uint256 amountOfTokens2) {
        amountOfTokens = bound(amountOfTokens, 2000, 19999);
        amountOfTokens2 = bound(amountOfTokens2, 20000, 1e30);

        ILaunchpad.UserTiers tier = _getTierByAmount(amountOfTokens);
        ILaunchpad.UserTiers tier2 = _getTierByAmount(amountOfTokens2);

        bytes memory signature = _getSignature(user, amountOfTokens);
        vm.prank(user);
        launchpad.register(address(testToken), tier, amountOfTokens, signature);

        signature = _getSignature(user3, amountOfTokens2);
        vm.prank(user3);
        launchpad.register(address(testToken), tier2, amountOfTokens2, signature);

        signature = _getSignature(user4, amountOfTokens2);
        vm.prank(user4);
        launchpad.register(address(testToken), tier2, amountOfTokens2, signature);

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.registrationEnd);
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

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.saleEnd);

        vm.startPrank(user);
        vm.expectRevert("BlastUP: invalid status");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);
        vm.stopPrank();
    }

    function test_RevertBuyTokens_VolumeIsZero() public placeTokens register {
        uint256 volume = 0;

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.publicSaleStart);

        vm.startPrank(user);

        vm.expectRevert("BlastUP: volume must be greater than 0");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);

        vm.stopPrank();
    }

    function test_RevertBuyTokens_ReceiverMustBeTheSender() public placeTokens register {
        uint256 volume = 100e18;

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.publicSaleStart);

        vm.startPrank(user);
        USDB.mint(user, volume + 1);
        USDB.approve(address(launchpad), volume + 1);
        vm.expectRevert("BlastUP: the receiver must be the sender");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user2);

        vm.stopPrank();
    }

    function test_RevertBuyTokens_NotEnoughAllocation() public placeTokens register {
        uint256 volume = 100e18;

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.publicSaleStart);

        vm.startPrank(user2);
        USDB.mint(user2, volume + 1);
        USDB.approve(address(launchpad), volume + 1);
        vm.expectRevert("BlastUP: You have not enough allocation");
        launchpad.buyTokens(address(testToken), address(USDB), volume, user2);

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
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(testToken));

        vm.warp(placedToken.publicSaleStart);

        uint256 sumLowTiersUsersAllowedAllocation = launchpad.userAllowedAllocation(address(testToken), user);
        assertApproxEqAbs(sumLowTiersUsersAllowedAllocation, placedToken.initialVolumeForLowTiers, 10);

        uint256 sumHighTiersUsersAllowedAllocation = launchpad.userAllowedAllocation(address(testToken), user3)
            + launchpad.userAllowedAllocation(address(testToken), user4);
        assertApproxEqAbs(sumHighTiersUsersAllowedAllocation, placedToken.initialVolumeForHighTiers, 10);

        _buyTokens(placedToken, user, address(USDB));
        _buyTokens(placedToken, user3, address(WETH));

        // TEST BUYING FROM STAKING
        _buyFromStaking(placedToken, user5, address(USDB));
        _buyFromStaking(placedToken, user6, address(WETH));

        // START FCFS ROUND
        vm.prank(admin);
        launchpad.setFCFSSaleStart(address(testToken), placedToken.publicSaleStart + 10);

        vm.warp(placedToken.publicSaleStart + 10);

        vm.startPrank(user);
        uint256 volume = 100;
        USDB.approve(address(launchpad), volume + 1);
        vm.expectRevert();
        launchpad.buyTokens(address(testToken), address(USDB), volume, user);
        vm.stopPrank();

        // expect revert buying by staking yield
        vm.startPrank(user5);
        uint256 rewardAmount;
        (, uint256 reward) = staking.balanceAndRewards(address(USDB), user5);
        uint256 _max = reward > placedToken.volumeForYieldStakers ? placedToken.volumeForYieldStakers : reward;
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
        ILaunchpad.User memory userInfoBefore = launchpad.userInfo(address(testToken), user3);
        uint256 tokensAmount = launchpad.userAllowedAllocation(address(testToken), user3) / 2;

        volume = tokensAmount * placedToken.price / (10 ** placedToken.tokenDecimals);
        volume /= 100;
        WETH.mint(user3, volume + 10);
        WETH.approve(address(launchpad), volume + 10);
        launchpad.buyTokens(address(testToken), address(WETH), volume, user3);

        ILaunchpad.User memory userInfo = launchpad.userInfo(address(testToken), user3);
        assertApproxEqAbs(userInfo.boughtAmount, userInfoBefore.boughtAmount + tokensAmount, tokensAmount / 100 + 1);
        vm.stopPrank();

        // endSale

        vm.startPrank(admin);
        launchpad.setSaleEnd(address(testToken), placedToken.publicSaleStart + 20);
        vm.warp(placedToken.publicSaleStart + 20);

        assertEq(launchpad.getClaimableAmount(address(testToken), user), 0);

        // set tge timestamp +5 seconds from currentStateEnd
        userInfo = launchpad.userInfo(address(testToken), user);
        placedToken = launchpad.getPlacedToken(address(testToken));

        launchpad.setTgeStart(address(testToken), placedToken.saleEnd + 5);
        assertEq(launchpad.getClaimableAmount(address(testToken), user), 0);
        vm.stopPrank();

        vm.warp(placedToken.saleEnd + 6);

        if (placedToken.tgePercent > 0) {
            assertEq(
                placedToken.tgePercent * userInfo.boughtAmount / 100,
                launchpad.getClaimableAmount(address(testToken), user)
            );
            // users claims their rewards
            _usersClaimRewardsTge(user);
            _usersClaimRewardsTge(user3);
            _usersClaimRewardsTge(user5);
        }
        vm.prank(admin);
        // set vesting start timestamp +5 seconds from now
        launchpad.setVestingStart(address(testToken), block.timestamp + 5);

        placedToken = launchpad.getPlacedToken(address(testToken));
        uint256 user4_claimableAmountBeforeVesting = launchpad.getClaimableAmount(address(testToken), user4);
        uint256 user6_claimableAmountBeforeVesting = launchpad.getClaimableAmount(address(testToken), user6);

        if (placedToken.tgePercent < 100) {
            vm.warp(placedToken.vestingStart + placedToken.vestingDuration / 2);
            _checkClaimableAmountDuringTheVestingPeriod(user4, user4_claimableAmountBeforeVesting);
            _checkClaimableAmountDuringTheVestingPeriod(user6, user6_claimableAmountBeforeVesting);
        }

        vm.warp(placedToken.vestingStart + placedToken.vestingDuration + 1);

        _checkClaimableAmountAfterTheVestingPeriod(user4);
        _checkClaimableAmountAfterTheVestingPeriod(user6);
    }
}
