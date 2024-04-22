// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {Launchpad, ERC20Mock, ILaunchpad, MessageHashUtils, ECDSA} from "../../BaseLaunchpad.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
    }

    mapping(address => PlacedTokenInvariants) ghost_placedToken;

    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    AddressSet internal _tokens;
    address internal currentActor;
    address internal currentToken;

    function getPlacedTokenInvariants(address token) external view returns (PlacedTokenInvariants memory) {
        return ghost_placedToken[token];
    }

    modifier createToken() {
        currentToken = address(new ERC20Mock("Token", "TKN", 18));
        _tokens.add(currentToken);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.randActor(actorIndexSeed);
        _;
    }

    modifier useToken(uint256 tokenIndexSeed) {
        currentToken = _tokens.randToken(tokenIndexSeed);
        vm.assume(currentToken != address(0));
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    constructor(Launchpad _launchpad, address _usdb, address _weth, uint256 _adminPrivateKey) {
        launchpad = _launchpad;
        usdb = _usdb;
        weth = _weth;
        adminPrivateKey = _adminPrivateKey;
    }

    function getSignature(address _user, uint256 _amountOfTokens) internal returns (bytes memory) {
        vm.startPrank(launchpad.owner());
        bytes32 digest = keccak256(abi.encodePacked(_user, _amountOfTokens, address(launchpad), block.chainid))
            .toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
        return signature;
    }

    function registerUser(address account, address token) external {
        uint256 _address = uint256(uint160(account) + _tokens.count());
        ILaunchpad.UserTiers tier = ILaunchpad.UserTiers(_address % 6);
        uint256 amountOfTokens = launchpad.minAmountForTier(tier) + _address % 10000;
        bytes memory signature = getSignature(account, amountOfTokens);

        vm.startPrank(account);
        launchpad.register(token, tier, amountOfTokens, signature);
        vm.stopPrank();
    }

    function sumAllowedAllocations(address account, address token) external {
        ghost_placedToken[token].sumUsersAllowedAllocation += launchpad.userAllowedAllocation(token, account);
    }

    function placeTokens(
        uint256 initialVolume,
        address addressForCollected,
        uint256 price,
        uint256 tgePercent,
        uint256 percentHighTiers
    ) public createToken countCall("placeTokens") {
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

        ILaunchpad.PlacedToken memory input = ILaunchpad.PlacedToken({
            price: price,
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            volumeForYieldStakers: volumeForYieldStakers,
            volume: initialVolume,
            addressForCollected: addressForCollected,
            registrationStart: block.timestamp + 1,
            registrationEnd: block.timestamp + 11,
            publicSaleStart: block.timestamp + 21,
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

        vm.startPrank(launchpad.owner());
        ERC20Mock(currentToken).mint(launchpad.owner(), initialVolume);
        ERC20Mock(currentToken).approve(address(launchpad), initialVolume + 1);
        launchpad.placeTokens(input, currentToken);
        vm.warp(block.timestamp + 1);
        vm.stopPrank();

        ghost_placedToken[currentToken].addressForCollected = addressForCollected;
        ghost_placedToken[currentToken].initialVolume = initialVolume;

        _actors.randActor(1);

        forEachActor(currentToken, this.registerUser);

        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));

        vm.warp(placedToken.publicSaleStart);

        forEachActor(currentToken, this.sumAllowedAllocations);
    }

    function buyTokens(uint256 actorSeed, uint256 tokenSeed, uint256 tokensAmount, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        useToken(tokenSeed)
        countCall("buyTokens")
    {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));

        vm.assume(status == ILaunchpad.SaleStatus.PUBLIC_SALE || status == ILaunchpad.SaleStatus.FCFS_SALE);

        address paymentContract = WETHOrUSDB ? usdb : weth;
        uint256 allowedAllocation = launchpad.userAllowedAllocation(currentToken, currentActor);
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
            ghost_placedToken[currentToken].sendedUSDB += volume;
        } else {
            volume = tokensAmount * placedToken.price / 1e20;
            ghost_placedToken[currentToken].sendedWETH += volume;
        }

        ILaunchpad.User memory userInfoBefore = launchpad.userInfo(currentToken, currentActor);

        vm.startPrank(currentActor);
        ERC20Mock(paymentContract).mint(currentActor, volume);
        ERC20Mock(paymentContract).approve(address(launchpad), volume);
        launchpad.buyTokens(currentToken, paymentContract, volume, currentActor);

        ILaunchpad.User memory userInfoAfter = launchpad.userInfo(currentToken, currentActor);
        vm.stopPrank();

        ghost_placedToken[currentToken].boughtAmount += userInfoAfter.boughtAmount - userInfoBefore.boughtAmount;
    }

    function setFCFSSaleStart(uint256 tokenSeed, uint256 _fcfsSaleStart) public useToken(tokenSeed) {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));
        vm.assume(status == ILaunchpad.SaleStatus.PUBLIC_SALE);
        _fcfsSaleStart = bound(_fcfsSaleStart, placedToken.publicSaleStart + 10, 1e50);
        vm.prank(launchpad.owner());
        launchpad.setFCFSSaleStart(currentToken, _fcfsSaleStart);
        vm.warp(_fcfsSaleStart);
    }

    function setSaleEnd(uint256 tokenSeed, uint256 _saleEnd) public useToken(tokenSeed) {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));
        vm.assume(status == ILaunchpad.SaleStatus.FCFS_SALE);
        _saleEnd = bound(_saleEnd, placedToken.fcfsSaleStart + 10, 1e50);
        vm.prank(launchpad.owner());
        launchpad.setSaleEnd(currentToken, _saleEnd);
        vm.warp(_saleEnd);
    }

    function setTgeStart(uint256 tokenSeed, uint256 _tgeStart) public useToken(tokenSeed) {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));
        vm.assume(status == ILaunchpad.SaleStatus.POST_SALE);
        _tgeStart = bound(_tgeStart, placedToken.saleEnd + 10, 1e50);
        vm.prank(launchpad.owner());
        launchpad.setTgeStart(currentToken, _tgeStart);
        vm.warp(_tgeStart);
    }

    function setVestingStart(uint256 tokenSeed, uint256 _vestingStart) public useToken(tokenSeed) {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));
        vm.assume(status == ILaunchpad.SaleStatus.POST_SALE);
        vm.assume(placedToken.tgeStart != type(uint256).max - 1);
        _vestingStart = bound(_vestingStart, placedToken.tgeStart + 10, 1e50);
        vm.prank(launchpad.owner());
        launchpad.setVestingStart(currentToken, _vestingStart);
        vm.warp(_vestingStart);
    }

    function claimRemainders(uint256 tokenSeed) public useToken(tokenSeed) {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));

        vm.assume(status == ILaunchpad.SaleStatus.POST_SALE);
        vm.assume(placedToken.volume > 0);
        vm.prank(launchpad.owner());
        launchpad.claimRemainders(currentToken);
    }

    function claimTokens(uint256 actorSeed, uint256 tokenSeed)
        public
        useActor(actorSeed)
        useToken(tokenSeed)
        countCall("claimTokens")
    {
        ILaunchpad.SaleStatus status = launchpad.getStatus(address(currentToken));
        vm.assume(status == ILaunchpad.SaleStatus.POST_SALE);

        uint256 claimableAmount = launchpad.getClaimableAmount(currentToken, currentActor);
        vm.assume(claimableAmount > 0);

        ghost_placedToken[currentToken].claimedAmount += claimableAmount;

        vm.startPrank(currentActor);
        launchpad.claimTokens(currentToken);
        vm.stopPrank();

        vm.warp(tokenSeed % 15);
    }

    function forEachActor(address _token, function(address, address) external func) public {
        return _actors.forEachPlusArgument(_token, func);
    }

    function forEachToken(function(address) external func) public {
        return _tokens.forEach(func);
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

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("placeTokens", calls["placeTokens"]);
        console.log("buyTokens", calls["buyTokens"]);
        console.log("startFCFSSale", calls["startFCFSSale"]);
        console.log("endSale", calls["endSale"]);
        console.log("claimTokens", calls["claimTokens"]);
        console.log("-------------------");
    }
}
