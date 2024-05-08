// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

contract BLPStaking is Ownable {
    using SafeERC20 for IERC20Metadata;

    struct UserState {
        uint256 balance;
        uint256 lastClaimTimestamp;
        uint256 unlockTimestamp;
        uint256 yearlyReward;
    }

    mapping(address => UserState) public users;
    mapping(uint256 => uint32) lockTimeToPercent;

    /// @notice Token being staked.
    IERC20Metadata public stakeToken;

    /// @notice Minimal balance for stake.
    uint256 public minBalance;

    /// @notice Counter of deposits - withdrawals. Contains amount of funds owned by users
    /// which are kept in the contract.
    uint256 public totalLocked;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakeToken, address _owner, address _points, address _pointsOperator) Ownable(_owner) {
        stakeToken = IERC20Metadata(_stakeToken);
        IBlastPoints(_points).configurePointsOperator(_pointsOperator);
    }

    /// @notice Ensures that balance of the contract is not lower than total amount owed to
    /// users besides rewards.
    modifier ensureSolvency() {
        _;
        require(stakeToken.balanceOf(address(this)) >= totalLocked, "BlastUP: insolvency");
    }

    /* ========== VIEWS ========== */

    function getRewardOf(address addr) public view returns (uint256) {
        UserState memory user = users[addr];

        uint256 elapsed =
            Math.min(block.timestamp - user.lastClaimTimestamp, user.unlockTimestamp - user.lastClaimTimestamp);
        return user.yearlyReward * elapsed / 365 days;
    }

    /* ========== FUNCTIONS ========== */

    function setMinBalance(uint256 _minBalance) external onlyOwner {
        minBalance = _minBalance;
    }

    /// @notice Maps a given lockTime in secods to yearly APY user can get by staking tokens for that period of time.
    function setLockTimeToPercent(uint256 lockTime, uint32 percent) external onlyOwner {
        lockTimeToPercent[lockTime] = percent;
    }

    /// @notice Stake given amount for given amount of time
    /// If user already has staked amount, lock is restarted.
    function stake(uint256 amount, uint256 lockTime) external {
        UserState storage user = users[msg.sender];
        uint32 percent = lockTimeToPercent[lockTime];

        require(percent > 0, "BlastUP: invalid lockTime");
        require(user.balance + amount > minBalance, "BlastUP: you must send more to stake");

        if (user.balance > 0) {
            claim();
        } else {
            user.lastClaimTimestamp = block.timestamp;
        }

        user.unlockTimestamp = block.timestamp + lockTime;
        user.balance += amount;
        user.yearlyReward = user.balance * percent / 1e4;
        totalLocked += amount;

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /// @notice Withdraw entire balance.
    /// @param force Whether to withdraw without claiming rewards. Should only be used in emergency
    /// cases when contract does not have enough funds to pay out rewards.
    function withdraw(bool force) public {
        UserState storage user = users[msg.sender];

        require(user.unlockTimestamp <= block.timestamp, "BlastUP: you must wait more to withdraw");
        require(user.balance > 0, "BlastUP: you haven't anything for withdraw");

        if (!force) {
            claim();
        }

        uint256 balance = user.balance;
        delete users[msg.sender];

        totalLocked -= balance;
        stakeToken.safeTransfer(msg.sender, balance);
        emit Withdrawn(msg.sender, balance);
    }

    function withdraw() external {
        withdraw(false);
    }

    /// @notice Claim all accrued rewards.
    function claim() public ensureSolvency returns (uint256 reward) {
        reward = getRewardOf(msg.sender);
        if (reward > 0) {
            UserState storage user = users[msg.sender];
            user.lastClaimTimestamp = block.timestamp > user.unlockTimestamp ? user.unlockTimestamp : block.timestamp;
            stakeToken.safeTransfer(msg.sender, reward);
            emit Claimed(msg.sender, reward);
        }
    }

    /// @notice Function for administrators to withdraw extra amounts sent to the contract
    /// for reward payouts.
    function withdrawFunds(uint256 amount) external onlyOwner ensureSolvency {
        stakeToken.safeTransfer(msg.sender, amount);
    }

    /* ========== EVENTS ========== */
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
}
