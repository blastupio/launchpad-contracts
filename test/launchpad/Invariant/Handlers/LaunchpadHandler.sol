// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {Launchpad, ERC20Mock, Types, MessageHashUtils, ECDSA} from "../../BaseLaunchpad.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract LaunchpadHandler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    Launchpad public launchpad;
    address internal immutable usdb;
    address internal immutable weth;
    uint256 internal immutable adminPrivateKey;

    struct PlacedTokenInvariants {
        uint256 claimedAmount;
        uint256 initialVolume;
        uint256 sendedETH;
        uint256 sendedWETH;
        uint256 sendedUSDB;
        address addressForCollected;
        uint256 boughtAmount;
        uint256 sumUsersAllowedAllocation;
        address token;
    }

    mapping(uint256 => PlacedTokenInvariants) ghost_placedToken;

    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    AddressSet internal _tokens;
    address internal currentActor;
    address internal currentToken;
    uint256 internal currentTokenId;

    function getPlacedTokenInvariants(uint256 id) external view returns (PlacedTokenInvariants memory) {
        return ghost_placedToken[id];
    }

    modifier createToken() {
        currentToken = address(new ERC20Mock("Token", "TKN", 18));
        currentTokenId = _tokens.count();
        _tokens.add(currentToken);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.randActor(actorIndexSeed);
        _;
    }

    modifier useToken(uint256 tokenIndexSeed) {
        (currentToken, currentTokenId) = _tokens.randToken(tokenIndexSeed);
        vm.assume(currentToken != address(0));
        _;
    }

    constructor(Launchpad _launchpad, address _usdb, address _weth, uint256 _adminPrivateKey) {
        launchpad = _launchpad;
        usdb = _usdb;
        weth = _weth;
        adminPrivateKey = _adminPrivateKey;
    }

    function _getSignature(address _user, uint256 _amountOfTokens) internal returns (bytes memory signature) {
        vm.startPrank(launchpad.owner());
        bytes32 digest = keccak256(abi.encodePacked(_user, _amountOfTokens, address(launchpad), block.chainid))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
    }

    function _getApproveSignature(address _user, uint256 _id) internal returns (bytes memory signature) {
        vm.startPrank(launchpad.owner());
        bytes32 digest =
            keccak256(abi.encodePacked(_user, _id, address(launchpad), block.chainid)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
    }

    function registerUser(address account, uint256 id) external {
        uint256 _address = uint256(uint160(account) + _tokens.count());
        Types.UserTiers tier = Types.UserTiers(_address % 6);
        uint256 amountOfTokens = launchpad.minAmountForTier(tier) + _address % 10000;
        bytes memory signature = _getSignature(account, amountOfTokens);
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(id);

        vm.startPrank(account);
        if (placedToken.approved) {
            bytes memory approveSignature = _getApproveSignature(account, id);
            launchpad.registerWithApprove(id, tier, amountOfTokens, signature, approveSignature);
        } else {
            launchpad.register(id, tier, amountOfTokens, signature);
        }
        vm.stopPrank();
    }

    function sumAllowedAllocations(address account, uint256 id) external {
        ghost_placedToken[id].sumUsersAllowedAllocation += launchpad.userAllowedAllocation(id, account);
    }

    function placeTokens(
        uint256 initialVolume,
        address addressForCollected,
        uint256 price,
        uint256 tgePercent,
        uint256 percentHighTiers
    ) public createToken {
        initialVolume = bound(initialVolume, 1e19, 1e38);
        addressForCollected =
            addressForCollected == address(0) ? address(uint160(initialVolume) * 2 / 3) : addressForCollected;

        price = bound(price, 1e5, 1e19);
        tgePercent = bound(tgePercent, 0, 100);
        percentHighTiers = bound(percentHighTiers, 50, 85);
        uint256 percentLowTiers = 95 - percentHighTiers;
        uint256 percentYieldStakers = 100 - percentLowTiers - percentHighTiers;

        uint256 initialVolumeForHighTiers = initialVolume * percentHighTiers;
        uint256 initialVolumeForLowTiers = initialVolume * percentLowTiers;
        uint256 volumeForYieldStakers = initialVolume * percentYieldStakers;
        uint256 vestingDuration = 60;
        initialVolume *= 100;

        Types.PlacedToken memory input = Types.PlacedToken({
            price: price,
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            volumeForYieldStakers: volumeForYieldStakers,
            volume: initialVolume,
            addressForCollected: addressForCollected,
            registrationStart: block.timestamp + 1,
            registrationEnd: block.timestamp + 2,
            publicSaleStart: block.timestamp + 3,
            fcfsSaleStart: type(uint256).max - 3,
            saleEnd: type(uint256).max - 2,
            tgeStart: type(uint256).max - 1,
            vestingStart: type(uint256).max,
            vestingDuration: vestingDuration,
            tgePercent: uint8(tgePercent),
            lowTiersWeightsSum: 0,
            highTiersWeightsSum: 0,
            tokenDecimals: 18,
            approved: false,
            token: currentToken,
            fcfsOpened: false,
            fcfsRequiredTier: Types.UserTiers.TITANIUM
        });

        vm.startPrank(launchpad.owner());
        ERC20Mock(currentToken).mint(launchpad.owner(), initialVolume);
        ERC20Mock(currentToken).approve(address(launchpad), initialVolume + 1);
        launchpad.placeTokens(input);
        vm.warp(block.timestamp + 1);
        vm.stopPrank();

        ghost_placedToken[currentTokenId].addressForCollected = addressForCollected;
        ghost_placedToken[currentTokenId].initialVolume = initialVolume;

        _actors.randActor(1);

        forEachActor(currentTokenId, this.registerUser);

        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);

        vm.warp(placedToken.publicSaleStart);

        forEachActor(currentTokenId, this.sumAllowedAllocations);
    }

    function buyTokens(uint256 actorSeed, uint256 tokenSeed, uint256 tokensAmount, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        useToken(tokenSeed)
    {
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);

        vm.assume(status == Types.SaleStatus.PUBLIC_SALE || status == Types.SaleStatus.FCFS_SALE);

        address paymentContract = WETHOrUSDB ? usdb : weth;
        uint256 allowedAllocation = launchpad.userAllowedAllocation(currentTokenId, currentActor);
        vm.assume(allowedAllocation > 0);

        uint256 maxTokensAmount =
            allowedAllocation * placedToken.price > 1e50 ? allowedAllocation / 1e10 : allowedAllocation;
        uint256 _decimals = WETHOrUSDB ? 1e18 : 1e20;
        if (_decimals / placedToken.price + 2 > maxTokensAmount) {
            return;
        }
        tokensAmount = bound(tokensAmount, _decimals / placedToken.price + 2, maxTokensAmount);
        uint256 volume;

        if (paymentContract == usdb) {
            volume = tokensAmount * placedToken.price / 1e18;
            ghost_placedToken[currentTokenId].sendedUSDB += volume;
        } else {
            volume = tokensAmount * placedToken.price / 1e20;
            ghost_placedToken[currentTokenId].sendedWETH += volume;
        }

        Types.User memory userInfoBefore = launchpad.userInfo(currentTokenId, currentActor);

        vm.startPrank(currentActor);
        ERC20Mock(paymentContract).mint(currentActor, volume);
        ERC20Mock(paymentContract).approve(address(launchpad), volume);
        launchpad.buyTokens(currentTokenId, paymentContract, volume, currentActor, bytes(""));

        Types.User memory userInfoAfter = launchpad.userInfo(currentTokenId, currentActor);
        vm.stopPrank();

        ghost_placedToken[currentTokenId].boughtAmount += userInfoAfter.boughtAmount - userInfoBefore.boughtAmount;
    }

    function setFCFSSaleStart(uint256 tokenSeed, uint256 _fcfsSaleStart) public useToken(tokenSeed) {
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);
        vm.assume(status == Types.SaleStatus.PUBLIC_SALE);
        vm.assume(placedToken.fcfsSaleStart > block.timestamp);
        _fcfsSaleStart = bound(_fcfsSaleStart, Math.max(placedToken.publicSaleStart + 100, block.timestamp + 1), 1e20);
        vm.prank(launchpad.owner());
        launchpad.setFCFSSaleStart(currentTokenId, _fcfsSaleStart);
    }

    function setSaleEnd(uint256 tokenSeed, uint256 _saleEnd) public useToken(tokenSeed) {
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);
        vm.assume(status == Types.SaleStatus.FCFS_SALE);
        vm.assume(placedToken.saleEnd > block.timestamp);
        _saleEnd = bound(_saleEnd, Math.max(placedToken.fcfsSaleStart + 100, block.timestamp + 1), 1e30);
        vm.prank(launchpad.owner());
        launchpad.setSaleEnd(currentTokenId, _saleEnd);
    }

    function setTgeStart(uint256 tokenSeed, uint256 _tgeStart) public useToken(tokenSeed) {
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);
        vm.assume(status == Types.SaleStatus.POST_SALE);
        vm.assume(placedToken.tgeStart > block.timestamp);
        _tgeStart = bound(_tgeStart, Math.max(placedToken.saleEnd + 100, block.timestamp + 1), 1e40);
        vm.prank(launchpad.owner());
        launchpad.setTgeStart(currentTokenId, _tgeStart);
    }

    function setVestingStart(uint256 tokenSeed, uint256 _vestingStart) public useToken(tokenSeed) {
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);
        vm.assume(status == Types.SaleStatus.POST_SALE);
        vm.assume(placedToken.tgeStart != type(uint256).max - 1);
        vm.assume(placedToken.vestingStart > block.timestamp);
        _vestingStart = bound(_vestingStart, Math.max(placedToken.tgeStart + 100, block.timestamp + 1), 1e60);
        vm.prank(launchpad.owner());
        launchpad.setVestingStart(currentTokenId, _vestingStart);
    }

    function claimRemainders(uint256 tokenSeed) public useToken(tokenSeed) {
        Types.PlacedToken memory placedToken = launchpad.getPlacedToken(currentTokenId);
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);

        vm.assume(status == Types.SaleStatus.POST_SALE);
        vm.assume(placedToken.volume > 0);
        vm.prank(launchpad.owner());
        launchpad.claimRemainders(currentTokenId);
    }

    function claimTokens(uint256 actorSeed, uint256 tokenSeed) public useActor(actorSeed) useToken(tokenSeed) {
        Types.SaleStatus status = launchpad.getStatus(currentTokenId);
        vm.assume(status == Types.SaleStatus.POST_SALE);

        uint256 claimableAmount = launchpad.getClaimableAmount(currentTokenId, currentActor);
        vm.assume(claimableAmount > 0);

        ghost_placedToken[currentTokenId].claimedAmount += claimableAmount;

        vm.startPrank(currentActor);
        launchpad.claimTokens(currentTokenId);
        vm.stopPrank();
    }

    function warp(uint256 secs) public {
        secs = _bound(secs, 0, 30 days);
        vm.warp(block.timestamp + secs);
    }

    function forEachActor(uint256 _id, function(address, uint256) external func) public {
        return _actors.forEachPlusArgument(_id, func);
    }

    function forEachToken(function(uint256) external func) public {
        for (uint256 i; i < _tokens.count(); ++i) {
            func(i);
        }
    }

    function reduceTokens(uint256 acc, function(uint256,address) external returns (uint256) func)
        public
        returns (uint256)
    {
        return _tokens.reduce(acc, func);
    }

    function tokens() external view returns (address[] memory) {
        return _tokens.addrs;
    }
}
