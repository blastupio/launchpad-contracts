// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.25;

import {CommonBase} from "forge-std/Base.sol";
import {StdAssertions} from "forge-std/StdAssertions.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {console} from "forge-std/console.sol";
import {AddressSet, LibAddressSet} from "../Helpers/AddressSet.sol";
import {BaseBLPStaking, BLPStaking, ERC20Mock} from "../../BaseBLPStaking.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {WadMath} from "../../../../src/libraries/WadMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BLPStakingHandler is CommonBase, StdCheats, StdUtils, StdAssertions {
    using LibAddressSet for AddressSet;
    using Math for uint256;

    BLPStaking public staking;
    ERC20Mock blp;

    uint256 public ghost_stakedSum;
    uint256 public ghost_rewardsClaimed;

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

    constructor(BLPStaking _staking, ERC20Mock _blp) {
        staking = _staking;
        blp = _blp;
    }

    function stake(uint256 amount, uint256 lockTime, uint8 percent) public createActor countCall("stake") {
        amount = bound(amount, 1e6, 1e40);
        percent = uint8(bound(percent, 1, 200));
        lockTime = bound(lockTime, 1e4, 1e15);

        blp.mint(currentActor, amount);

        vm.prank(staking.owner());
        staking.setLockTimeToPercent(lockTime, percent);

        (uint256 balance,,,) = staking.users(currentActor);

        if (balance > 0) {
            uint256 reward = staking.getRewardOf(currentActor);
            ghost_rewardsClaimed += reward;
        }

        vm.startPrank(currentActor);
        blp.approve(address(staking), amount);
        staking.stake(amount, lockTime);
        vm.stopPrank();

        ghost_stakedSum += amount;
    }

    function withdraw(uint256 actorSeed) public useActor(actorSeed) {
        uint256 reward = staking.getRewardOf(currentActor);
        (uint256 balance,, uint256 unlockTimestamp,) = staking.users(currentActor);

        vm.assume(unlockTimestamp <= block.timestamp);
        vm.assume(balance > 0);

        vm.prank(currentActor);
        staking.withdraw();

        ghost_stakedSum -= balance;
        ghost_rewardsClaimed += reward;
    }

    function claim(uint256 actorSeed) public useActor(actorSeed) {
        uint256 reward = staking.getRewardOf(currentActor);
        vm.prank(currentActor);
        staking.claim();
        ghost_rewardsClaimed += reward;
    }

    function forceWithdrawAll(uint256 actorSeed)
        public
        useActor(actorSeed)
        countCall("forceWithdrawAll")
    {
        (uint256 balance,, uint256 unlockTimestamp,) = staking.users(currentActor);
        vm.assume(balance > 0);
        if (block.timestamp < unlockTimestamp) {
            vm.warp(unlockTimestamp);
        }

        uint256 reward = staking.getRewardOf(currentActor);

        ghost_stakedSum -= balance;
        ghost_rewardsClaimed += reward;

        vm.prank(currentActor);
        staking.withdraw();
    }

    function warp(uint256 secs) public {
        secs = _bound(secs, 0, 20 days);
        vm.warp(block.timestamp + secs);
    }
}
