// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {
    BaseStakingTest,
    YieldStaking,
    WadMath,
    ERC20Mock,
    ERC20RebasingMock,
    Launchpad,
    MessageHashUtils
} from "../../BaseStaking.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WadMath} from "../../../../src/libraries/WadMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract StakingHandler is CommonBase, StdCheats, StdUtils, StdAssertions {
    using LibAddressSet for AddressSet;
    using WadMath for uint256;
    using Math for uint256;
    using MessageHashUtils for bytes32;

    YieldStaking public staking;
    address internal immutable usdb;
    address internal immutable weth;
    Launchpad internal launchpad;
    uint256 internal immutable adminPrivateKey;

    mapping(address => uint256) public ghost_stakedSums;
    mapping(address token => mapping(address user => uint256 amount)) deposited;

    mapping(bytes32 => uint256) public calls;

    AddressSet internal _actors;
    address internal currentActor;

    modifier createActor() {
        currentActor = msg.sender;
        _actors.add(msg.sender);
        _;
    }

    modifier useActor(uint256 actorIndexSeed) {
        currentActor = _actors.rand(actorIndexSeed);
        _;
    }

    modifier countCall(bytes32 key) {
        calls[key]++;
        _;
    }

    function getActors() public view returns (address[] memory) {
        return _actors.addrs;
    }

    constructor(YieldStaking _staking, address _usdb, address _weth, Launchpad _launchpad, uint256 _adminPrivateKey) {
        staking = _staking;
        usdb = _usdb;
        weth = _weth;
        launchpad = _launchpad;
        adminPrivateKey = _adminPrivateKey;
    }

    function getUserBalance(address token, address user) public view returns (uint256) {
        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(token, user);

        return balance + rewards;
    }

    function _increaseGhostWithRewards(address token) internal {
        ghost_stakedSums[token] += ERC20RebasingMock(token).getClaimableAmount(address(staking));
    }

    function _getApproveSignature(address _user, address _token) internal returns (bytes memory signature) {
        vm.startPrank(launchpad.owner());
        bytes32 digest =
            keccak256(abi.encodePacked(_user, _token, address(launchpad), block.chainid)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(adminPrivateKey, digest);
        signature = abi.encodePacked(r, s, v);
        vm.stopPrank();
    }

    function stake(uint256 amount, bool WETHOrUSDB) public createActor countCall("stake") {
        address depositToken = WETHOrUSDB ? usdb : weth;
        amount = _bound(amount, 0, 1_000_000_000 * 10 ** IERC20Metadata(depositToken).decimals());

        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(depositToken, currentActor);
        uint256 balanceAfter = balance + rewards + amount;
        uint256 usdbValue;
        if (depositToken == usdb) {
            usdbValue = balanceAfter;
        } else {
            (, int256 wethPrice,,,) = staking.oracle().latestRoundData();
            usdbValue =
                balanceAfter * uint256(wethPrice) * (10 ** IERC20Metadata(usdb).decimals()) / ((10 ** 18) * (10 ** 8));
        }

        uint256 minAmountToStake = staking.minUSDBStakeValue();
        staking.userInfo(depositToken, currentActor);

        vm.startPrank(currentActor);
        ERC20Mock(depositToken).mint(currentActor, amount);
        IERC20(depositToken).approve(address(staking), amount);

        _increaseGhostWithRewards(depositToken);
        if (usdbValue < minAmountToStake) {
            vm.expectRevert();
            staking.stake(depositToken, amount);
            return;
        }

        ghost_stakedSums[depositToken] += amount;
        deposited[depositToken][currentActor] += amount;

        (uint256 balanceBefore, uint256 rewardsBefore) = staking.balanceAndRewards(depositToken, currentActor);
        staking.stake(depositToken, amount);
        uint256 rewardsAfter;
        (balanceAfter, rewardsAfter) = staking.balanceAndRewards(depositToken, currentActor);
        assertEq(balanceAfter, balanceBefore + amount);
        assertEq(rewardsAfter, rewardsBefore);
    }

    function withdraw(uint256 actorSeed, uint256 amount, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        countCall("withdraw")
    {
        address targetToken = WETHOrUSDB ? usdb : weth;
        (uint256 balanceOfUser,) = staking.balanceAndRewards(targetToken, currentActor);

        YieldStaking.StakingUser memory user = staking.userInfo(targetToken, currentActor);

        amount = _bound(amount, 0, balanceOfUser);
        vm.assume(amount > 0);
        vm.assume(block.timestamp >= user.timestampToWithdraw);

        _increaseGhostWithRewards(targetToken);
        ghost_stakedSums[targetToken] -= amount;
        deposited[targetToken][currentActor] -= amount;

        (uint256 balanceBefore, uint256 rewardsBefore) = staking.balanceAndRewards(targetToken, currentActor);
        vm.startPrank(currentActor);
        staking.withdraw(targetToken, amount, false);
        (uint256 balanceAfter, uint256 rewardsAfter) = staking.balanceAndRewards(targetToken, currentActor);
        assertEq(balanceAfter, balanceBefore - amount);
        assertEq(rewardsAfter, rewardsBefore);
    }

    function claimReward(uint256 actorSeed, uint256 rewardAmount, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        countCall("claimReward")
    {
        address targetToken = WETHOrUSDB ? usdb : weth;
        address rewardToken = targetToken;

        (, uint256 rewardOfUser) = staking.balanceAndRewards(targetToken, currentActor);
        rewardAmount = _bound(rewardAmount, 0, rewardOfUser);

        vm.assume(rewardAmount > 0);

        _increaseGhostWithRewards(targetToken);
        ghost_stakedSums[targetToken] -= rewardAmount;

        uint256 balanceBefore = getUserBalance(rewardToken, currentActor);
        bytes memory approveSignature = _getApproveSignature(currentActor, rewardToken);
        vm.startPrank(currentActor);
        staking.claimReward(targetToken, rewardToken, rewardAmount, false, approveSignature, 0);
        assertEq(getUserBalance(rewardToken, currentActor), balanceBefore - rewardAmount);
    }

    // Ensure that user can always withdraw his funds in full.
    function forceWithdrawAll(uint256 actorSeed, bool useWETH)
        public
        useActor(actorSeed)
        countCall("forceWithdrawAll")
    {
        address token = useWETH ? weth : usdb;
        YieldStaking.StakingUser memory user = staking.userInfo(token, currentActor);
        if (block.timestamp < user.timestampToWithdraw) {
            vm.warp(user.timestampToWithdraw);
        }
        uint256 amount = deposited[token][currentActor];

        _increaseGhostWithRewards(token);
        ghost_stakedSums[token] -= amount;
        deposited[token][currentActor] = 0;

        uint256 balanceBefore = getUserBalance(token, currentActor);
        vm.startPrank(currentActor);
        staking.withdraw(token, amount, false);
        assertEq(getUserBalance(token, currentActor), balanceBefore - amount);
    }

    function setMinTimeToWithdraw(uint256 amount) public countCall("setMinTimeToWithdraw") {
        amount = _bound(amount, 0, 10 ** 5);
        vm.startPrank(staking.owner());
        staking.setMinTimeToWithdraw(amount);
        vm.stopPrank();
    }

    function setMinUSDBStakeValue(uint256 amount) public countCall("setMinUSDBStakeValue") {
        amount = _bound(amount, 0, 1e6 * 1e18);
        vm.startPrank(staking.owner());
        staking.setMinUSDBStakeValue(amount);
        vm.stopPrank();
    }

    function warp(uint256 secs) public {
        secs = _bound(secs, 0, 30 days);
        vm.warp(block.timestamp + secs);
    }

    function addRewards(bool isWeth, uint256 amount) public {
        address token = isWeth ? weth : usdb;
        uint256 index = staking.lastIndex(token);

        vm.assume(index < 1e23);
        amount = _bound(amount, 0, 1_000 * (10 ** IERC20Metadata(token).decimals()));
        ERC20RebasingMock(token).addRewards(address(staking), amount);
    }
}
