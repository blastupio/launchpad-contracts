// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BLPStaking is Ownable {
    using SafeERC20 for IERC20Metadata;

    struct UserState {
        uint256 balance;
        uint256 lastClaimTimestamp;
        uint256 unlockTimestamp;
        uint8 percent;
    }

    mapping(address => UserState) users;
    mapping(uint256 => uint8) lockTimeToPercent;

    IERC20Metadata public stakeToken;
    uint256 public minBalance;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _stakeToken, address admin) Ownable(admin) {
        stakeToken = IERC20Metadata(_stakeToken);
    }

    /* ========== VIEWS ========== */

    function getRewardOf(address addr) public view returns (uint256) {
        UserState memory user = users[addr];

        uint256 slope = user.balance * user.percent * 1e16 / 1e18;
        uint256 time =
            Math.min(block.timestamp - user.lastClaimTimestamp, user.unlockTimestamp - user.lastClaimTimestamp);
        return slope * time / 365 days;
    }

    function getUserState(address user) external view returns (UserState memory) {
        return users[user];
    }

    /* ========== FUNCTIONS ========== */

    function setMinBalance(uint256 _minBalance) external onlyOwner {
        minBalance = _minBalance;
    }

    function setLockTimeToPercent(uint256 lockTime, uint8 percent) external onlyOwner {
        lockTimeToPercent[lockTime] = percent;
    }

    function removeLockTimeToPercent(uint256 lockTime) external onlyOwner {
        delete lockTimeToPercent[lockTime];
    }

    function stake(uint256 amount, uint256 lockTime) external {
        UserState storage user = users[msg.sender];
        uint256 percent = lockTimeToPercent[lockTime];

        require(percent > 0, "BlastUP: invalid lockTime");
        require(user.balance + amount > minBalance, "BlastUP: you must send more to stake");

        if (user.balance > 0) {
            claim();
        }

        user.unlockTimestamp = block.timestamp + lockTime;
        user.balance += amount;
        user.percent = lockTimeToPercent[lockTime];

        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw() external {
        UserState storage user = users[msg.sender];

        require(user.unlockTimestamp <= block.timestamp, "BlastUP: you must wait more to withdraw");
        require(user.balance > 0, "BlastUP: you haven't anything for withdraw");

        claim();
        uint256 balance = user.balance;
        user.balance = 0;

        stakeToken.safeTransfer(msg.sender, balance);
        emit Withdrawn(msg.sender, balance);
    }

    function claim() public returns (uint256 reward) {
        reward = getRewardOf(msg.sender);
        if (reward > 0) {
            users[msg.sender].lastClaimTimestamp = block.timestamp;
            stakeToken.safeTransfer(msg.sender, reward);
            emit Claimed(msg.sender, reward);
        }
    }

    /* ========== EVENTS ========== */
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event Claimed(address indexed user, uint256 amount);
}
