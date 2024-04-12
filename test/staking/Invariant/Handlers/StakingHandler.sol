// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {BaseStakingTest, Staking, WadMath, ERC20Mock, ERC20RebasingMock} from "../../BaseStaking.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WadMath} from "../../../../src/libraries/WadMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract StakingHandler is CommonBase, StdCheats, StdUtils, StdAssertions {
    using LibAddressSet for AddressSet;
    using WadMath for uint256;
    using Math for uint256;

    Staking public staking;
    address internal immutable usdb;
    address internal immutable weth;

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

    constructor(Staking _staking, address _usdb, address _weth) {
        staking = _staking;
        usdb = _usdb;
        weth = _weth;
    }

    function _getUserBalance(address token, address user) internal view returns (uint256) {
        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(token, user);

        return balance + rewards;
    }

    function _increaseGhostWithRewards(address token) internal {
        ghost_stakedSums[token] += ERC20RebasingMock(token).getClaimableAmount(address(staking));
    }

    function stake(uint256 amount, bool WETHOrUSDB) public createActor countCall("stake") {
        address depositToken = WETHOrUSDB ? usdb : weth;
        amount = _bound(amount, 0, 10 ** IERC20Metadata(depositToken).decimals());

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

        if (usdbValue < minAmountToStake) {
            vm.expectRevert();
            staking.stake(depositToken, amount);
            return;
        }

        _increaseGhostWithRewards(depositToken);
        ghost_stakedSums[depositToken] += amount;
        deposited[depositToken][currentActor] += amount;

        uint256 balanceBefore = _getUserBalance(depositToken, currentActor);
        staking.stake(depositToken, amount);
        assertGe(_getUserBalance(depositToken, currentActor), balanceBefore + amount);
    }

    function withdraw(uint256 actorSeed, uint256 amount, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        countCall("withdraw")
    {
        address targetToken = WETHOrUSDB ? usdb : weth;
        (uint256 balanceOfUser,) = staking.balanceAndRewards(targetToken, currentActor);

        Staking.StakingUser memory user = staking.userInfo(targetToken, currentActor);

        amount = _bound(amount, 0, balanceOfUser);
        vm.assume(amount > 0);
        vm.assume(block.timestamp >= user.timestampToWithdraw);

        _increaseGhostWithRewards(targetToken);
        ghost_stakedSums[targetToken] -= amount;
        if (amount > deposited[targetToken][currentActor]) {
            deposited[targetToken][currentActor] = 0;
        } else {
            deposited[targetToken][currentActor] -= amount;
        }

        vm.startPrank(currentActor);
        staking.withdraw(targetToken, amount, false);
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

        vm.startPrank(currentActor);
        staking.claimReward(targetToken, rewardToken, rewardAmount, false);
    }

    // Ensure that user can always withdraw his funds in full.
    function forceWithdrawAll(uint256 actorSeed, bool useWETH)
        public
        useActor(actorSeed)
        countCall("forceWithdrawAll")
    {
        address token = useWETH ? weth : usdb;
        Staking.StakingUser memory user = staking.userInfo(token, currentActor);
        if (block.timestamp < user.timestampToWithdraw) {
            vm.warp(user.timestampToWithdraw);
        }
        uint256 amount = deposited[token][currentActor];

        _increaseGhostWithRewards(token);
        ghost_stakedSums[token] -= amount;
        deposited[token][currentActor] = 0;

        vm.startPrank(currentActor);
        staking.withdraw(token, amount, false);
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
}
