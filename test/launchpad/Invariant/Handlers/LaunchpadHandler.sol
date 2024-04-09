// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {
    BaseLaunchpadTest,
    Launchpad,
    ERC20Mock,
    ERC20RebasingMock,
    ILaunchpad,
    MessageHashUtils,
    ECDSA
} from "../../BaseLaunchpad.t.sol";
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

    // mapping(address => uint256) public ghost_stakedSums;
    // mapping(address => uint256) public ghost_tokensVolume;
    mapping(address => PlacedTokenInvariants) ghost_placedToken;

    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    AddressSet internal _tokens;
    address internal currentActor;
    address internal currentToken;

    function getPlacedTokenInvariants(address token) external view returns (PlacedTokenInvariants memory) {
        return ghost_placedToken[token];
    }

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
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
        if (currentToken == address(0)) {
            currentToken = address(new ERC20Mock("Token", "TKN", 18));
            _tokens.add(currentToken);
        }
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
        uint256 volumeForHighTiers
    ) public createToken countCall("placeTokens") {
        initialVolume = bound(initialVolume, 1e21, 1e38);

        price = bound(price, 1e3, 1e19);
        tgePercent = bound(tgePercent, 0, 100);
        volumeForHighTiers = bound(volumeForHighTiers, 50, 90);
        uint256 volumeForLowTiers = 95 - volumeForHighTiers;
        uint256 volumeForYieldStakers = 100 - volumeForLowTiers - volumeForHighTiers;

        uint256 initialVolumeForHighTiers = initialVolume * volumeForHighTiers / 100;
        uint256 initialVolumeForLowTiers = initialVolume * volumeForLowTiers / 100;
        uint256 initialVolumeForYieldStakers = initialVolume * volumeForYieldStakers / 100;
        uint256 vestingDuration = 60;

        ILaunchpad.PlaceTokensInput memory input = ILaunchpad.PlaceTokensInput({
            price: price,
            token: currentToken,
            initialVolumeForHighTiers: initialVolumeForHighTiers,
            initialVolumeForLowTiers: initialVolumeForLowTiers,
            initialVolumeForYieldStakers: initialVolumeForYieldStakers,
            timeOfEndRegistration: block.timestamp + 100,
            addressForCollected: addressForCollected,
            vestingDuration: vestingDuration,
            tgePercent: uint8(tgePercent)
        });

        vm.startPrank(launchpad.owner());
        ERC20Mock(currentToken).mint(launchpad.owner(), initialVolume);
        ERC20Mock(currentToken).approve(address(launchpad), initialVolume + 1);
        launchpad.placeTokens(input);
        vm.stopPrank();

        ghost_placedToken[currentToken].addressForCollected = addressForCollected;
        ghost_placedToken[currentToken].initialVolume = initialVolume;

        _actors.randActor(1);

        forEachActor(currentToken, this.registerUser);

        vm.startPrank(launchpad.owner());
        launchpad.endRegistration(currentToken);
        launchpad.startPublicSale(currentToken, block.timestamp + 100);
        vm.stopPrank();

        forEachActor(currentToken, this.sumAllowedAllocations);
    }

    function buyTokens(uint256 actorSeed, uint256 tokenSeed, uint256 volume, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        useToken(tokenSeed)
        countCall("buyTokens")
    {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        if (
            placedToken.status != ILaunchpad.SaleStatus.PUBLIC_SALE
                && placedToken.status != ILaunchpad.SaleStatus.FCFS_SALE
        ) {
            return;
        }
        address paymentContract = WETHOrUSDB ? usdb : weth;

        uint256 allowedAllocation = launchpad.userAllowedAllocation(currentToken, currentActor);
        volume = bound(volume, placedToken.price / placedToken.tokenDecimals + 1, allowedAllocation);

        uint256 boughtAmount;

        if (paymentContract == usdb) {
            ghost_placedToken[currentToken].sendedUSDB += volume;
            boughtAmount = volume * (10 ** placedToken.tokenDecimals) / placedToken.price;
        } else {
            ghost_placedToken[currentToken].sendedWETH += volume;
            boughtAmount = volume * 100 * (10 ** placedToken.tokenDecimals) / placedToken.price;
        }

        ghost_placedToken[currentToken].boughtAmount += boughtAmount;

        vm.startPrank(currentActor);
        launchpad.buyTokens(currentToken, paymentContract, volume, currentActor);
        vm.stopPrank();
    }

    function startFCFSSale(uint256 tokenSeed, uint256 endTimeOfTheRound)
        public
        useToken(tokenSeed)
        countCall("startFCFSSale")
    {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));

        if (placedToken.status != ILaunchpad.SaleStatus.PUBLIC_SALE) {
            return;
        }

        vm.startPrank(launchpad.owner());
        launchpad.startFCFSSale(currentToken, endTimeOfTheRound);
        vm.stopPrank();
    }

    function endSale(uint256 tokenSeed, address receiver) public useToken(tokenSeed) countCall("endSale") {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));

        if (placedToken.status != ILaunchpad.SaleStatus.FCFS_SALE) {
            return;
        }

        vm.startPrank(launchpad.owner());
        launchpad.setTgeTimestamp(currentToken, block.timestamp);
        launchpad.setVestingStartTimestamp(currentToken, block.timestamp + 15);
        launchpad.endSale(currentToken, receiver);
        vm.stopPrank();
    }

    function claimTokens(uint256 actorSeed, uint256 tokenSeed)
        public
        useActor(actorSeed)
        useToken(tokenSeed)
        countCall("claimTokens")
    {
        ILaunchpad.PlacedToken memory placedToken = launchpad.getPlacedToken(address(currentToken));
        if (placedToken.status != ILaunchpad.SaleStatus.POST_SALE) {
            return;
        }

        uint256 claimableAmount = launchpad.getClaimableAmount(currentToken, currentActor);

        if (claimableAmount == 0) {
            return;
        }

        ghost_placedToken[currentToken].claimedAmount += claimableAmount;
        vm.warp(tokenSeed % 15);

        vm.startPrank(currentActor);
        launchpad.claimTokens(currentToken);
        vm.stopPrank();
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
