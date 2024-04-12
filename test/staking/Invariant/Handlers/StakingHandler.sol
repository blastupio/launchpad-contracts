// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {BaseStakingTest, Staking, WadMath, ERC20Mock, ERC20RebasingMock} from "../../BaseStaking.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WadMath} from "../../../../src/libraries/WadMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract StakingHandler is CommonBase, StdCheats, StdUtils {
    using LibAddressSet for AddressSet;
    using WadMath for uint256;
    using Math for uint256;

    Staking public staking;
    address internal immutable usdb;
    address internal immutable weth;

    mapping(address => uint256) public ghost_stakedSums;

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

    function _stake(uint256 amount, bool WETHOrUSDB, address actor) internal {
        address depositToken = WETHOrUSDB ? usdb : weth;

        if (staking.lastIndex(depositToken) > 1e28) {
            return;
        }

        uint256 increaseStakedAmount = ERC20RebasingMock(depositToken).getClaimableAmount(address(staking)) + amount;
        ghost_stakedSums[depositToken] += increaseStakedAmount;

        vm.startPrank(actor);
        ERC20Mock(depositToken).mint(actor, amount);
        console.log("Actor balance", actor, IERC20(depositToken).balanceOf(actor));
        IERC20(depositToken).approve(address(staking), amount);
        console.log("Actor allowance", actor, IERC20(depositToken).allowance(actor, address(staking)));
        staking.stake(depositToken, amount);
        (uint256 balance, uint256 rewards) = staking.balanceAndRewards(depositToken, actor);
        console.log("Actor staked balance and rewards", balance, rewards);
        vm.stopPrank();
    }

    function stake(uint256 amount, bool WETHOrUSDB) public createActor countCall("stake") {
        uint256 minAmountToStake = staking.minUSDBStakeValue() + 10;
        address depositToken = WETHOrUSDB ? usdb : weth;
        if (!WETHOrUSDB) {
            minAmountToStake = (minAmountToStake + 1000) / 100;
        }

        uint256 _lastIndex = staking.lastIndex(depositToken);
        uint256 _amount = minAmountToStake.wadDiv(_lastIndex).wadMul(_lastIndex);
        console.log("_amount", _amount);
        if (_amount == 0) {
            _amount = _lastIndex / 1e10;
        }
        if (_amount < minAmountToStake) {
            _amount *= (_lastIndex / 1e10);
        }
        amount = bound(amount, Math.min(_amount * 1e6, 1e36 - 2) + 1, 1e36);

        _stake(amount, WETHOrUSDB, currentActor);
    }

    function withdraw(uint256 actorSeed, uint256 amount, bool WETHOrUSDB)
        public
        useActor(actorSeed)
        countCall("withdraw")
    {
        address targetToken = WETHOrUSDB ? usdb : weth;
        if (staking.lastIndex(targetToken) > 1e28) {
            return;
        }

        (uint256 balanceOfUser,) = staking.balanceAndRewards(targetToken, currentActor);

        if (balanceOfUser == 0) {
            uint256 minAmountToStake = staking.minUSDBStakeValue() + 10;
            if (!WETHOrUSDB) {
                minAmountToStake = (minAmountToStake + 1000) / 100;
            }
            uint256 _lastIndex = staking.lastIndex(targetToken);
            uint256 _amount = minAmountToStake.wadDiv(_lastIndex).wadMul(_lastIndex);
            console.log("_amount", _amount);
            if (_amount == 0) {
                _amount = _lastIndex / 1e10;
            }
            if (_amount < minAmountToStake) {
                _amount *= (_lastIndex / 1e10);
            }

            amount = bound(amount, Math.min(_amount * 1e6, 1e36 - 2) + 1, 1e36);
            _stake(amount, WETHOrUSDB, currentActor);
            (balanceOfUser,) = staking.balanceAndRewards(targetToken, currentActor);
        }
        amount = bound(amount, 1, balanceOfUser);

        uint256 increaseStakedAmount = ERC20RebasingMock(targetToken).getClaimableAmount(address(staking));
        ghost_stakedSums[targetToken] += increaseStakedAmount;
        ghost_stakedSums[targetToken] -= amount;

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

        if (staking.lastIndex(targetToken) > 1e28) {
            return;
        }
        Staking.StakingUser memory userInfo = staking.userInfo(targetToken, currentActor);
        console.log("user: ", userInfo.balanceScaled, userInfo.amountDeposited, userInfo.remainders);
        (, uint256 rewardOfUser) = staking.balanceAndRewards(targetToken, currentActor);

        if (rewardOfUser == 0) {
            uint256 minAmountToStake = staking.minUSDBStakeValue() + 10;
            if (!WETHOrUSDB) {
                minAmountToStake = (minAmountToStake + 1000) / 100;
            }
            uint256 _lastIndex = staking.lastIndex(targetToken);
            uint256 _amount = minAmountToStake.wadDiv(_lastIndex).wadMul(_lastIndex);
            console.log("_amount", _amount);
            if (_amount == 0) {
                _amount = _lastIndex / 1e10;
            }
            if (_amount < minAmountToStake) {
                _amount *= (_lastIndex / 1e10);
            }
            rewardAmount = bound(rewardAmount, Math.min(_amount * 1e6, 1e36 - 2) + 1, 1e36);
            _stake(rewardAmount * 25, WETHOrUSDB, currentActor);
            (, rewardOfUser) = staking.balanceAndRewards(targetToken, currentActor);
        }
        rewardAmount = bound(rewardAmount, 0, rewardOfUser);

        uint256 increaseStakedAmount = ERC20RebasingMock(targetToken).getClaimableAmount(address(staking));
        ghost_stakedSums[targetToken] += increaseStakedAmount;
        ghost_stakedSums[targetToken] -= rewardAmount;

        vm.startPrank(currentActor);
        staking.claimReward(targetToken, rewardToken, rewardAmount, false);
    }

    function setMinTimeToWithdraw(uint256 amount) public countCall("setMinTimeToWithdraw") {
        amount = bound(amount, 0, 10 ** 5);
        vm.startPrank(staking.owner());
        staking.setMinTimeToWithdraw(amount);
        vm.stopPrank();
    }

    function setMinUSDBStakeValue(uint256 amount) public countCall("setMinUSDBStakeValue") {
        amount = bound(amount, 0, 1e6 * 1e18);
        vm.startPrank(staking.owner());
        staking.setMinUSDBStakeValue(amount);
        vm.stopPrank();
    }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("stake", calls["stake"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("claimReward", calls["claimReward"]);
        console.log("setMinUSDBStakeValue", calls["setMinUSDBStakeValue"]);
        console.log("-------------------");
    }
}
