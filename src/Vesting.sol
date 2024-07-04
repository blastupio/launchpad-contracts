// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title Vesting
 * @dev This contract is designed for managing token sales with vesting schedules.
 */
contract Vesting is Ownable {
    using SafeERC20 for IERC20;

    // Represents user details in the vesting process.
    struct User {
        // Amount of tokens user have already claimed.
        uint256 claimedAmount;
        // Total amount of tokens user have bought during sale.
        uint256 balance;
    }

    /* ========== STORAGE VARIABLES =========== */

    // The address authorized to issue the initial balances of users
    address public operator;
    uint256 public tgeTimestamp;
    uint256 public vestingStart;
    uint256 public vestingDuration;
    uint8 public tgePercent;

    // Token being distributed in the sale.
    IERC20 public token;

    mapping(address user => User) public users;

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Initializes the contract with the specified parameters.
     * @param dao The address of the DAO, which will be the initial owner.
     * @param _operator The address of the operator.
     * @param _token The address of the token being sold.
     */
    constructor(
        address dao,
        address _operator,
        address _token,
        uint256 _tgeTimestamp,
        uint256 _vestingStart,
        uint256 _vestingDuration,
        uint8 _tgePercent
    ) Ownable(dao) {
        tgeTimestamp = _tgeTimestamp;
        tgePercent = _tgePercent;
        vestingStart = _vestingStart;
        vestingDuration = _vestingDuration;
        operator = _operator;
        token = IERC20(_token);
    }

    modifier onlyOperatorOrOwner() {
        require(msg.sender == operator || msg.sender == owner(), "BlastUP: caller is not the operator");
        _;
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Calculates the amount of tokens a user can claim based on the vesting schedule.
     * @param user The address of the user.
     * @return The number of tokens the user can claim.
     */
    function getClaimableAmount(address user) public view returns (uint256) {
        // If current time is before TGE, return 0.
        if (block.timestamp < tgeTimestamp) return 0;

        // Tokens available at TGE.
        uint256 tgeAmount = users[user].balance * tgePercent / 100;
        if (block.timestamp < vestingStart) return tgeAmount - users[user].claimedAmount;

        uint256 totalVestedAmount = users[user].balance - tgeAmount;
        uint256 elapsed = Math.min(block.timestamp - vestingStart, vestingDuration);
        uint256 vestedAmount = elapsed * totalVestedAmount / vestingDuration;

        return tgeAmount + vestedAmount - users[user].claimedAmount;
    }

    function setTgeTimestamp(uint256 newTgeTimestamp) external onlyOwner {
        require(newTgeTimestamp > block.timestamp, "BlastUP: invalid tge timestamp");
        require(tgeTimestamp > block.timestamp, "BlastUP: can't change TGE after TGE start");
        tgeTimestamp = newTgeTimestamp;
    }

    function setVestingStart(uint256 newVestingStart) external onlyOwner {
        require(newVestingStart > block.timestamp, "BlastUP: invalid vesting start");
        require(vestingStart > block.timestamp, "BlastUP: vesting already started");
        vestingStart = newVestingStart;
    }

    function setVestingDuration(uint256 _vestingDuration) external onlyOwner {
        require(vestingStart > block.timestamp, "BlastUP: vesting already started");
        vestingDuration = _vestingDuration;
    }

    function setTgePercent(uint8 _tgePercent) external onlyOwner {
        require(tgeTimestamp > block.timestamp, "BlastUP: can't change TGE after TGE start");
        tgePercent = _tgePercent;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    /**
     * @notice Sets the token balances for multiple users.
     * @param accounts The list of user addresses.
     * @param amounts The list of corresponding token amounts.
     */
    function setBalances(address[] memory accounts, uint256[] memory amounts) external onlyOperatorOrOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            users[accounts[i]].balance = amounts[i];
        }
    }

    /**
     * @notice Allows users to claim their available tokens.
     */
    function claim() external {
        uint256 amount = getClaimableAmount(msg.sender);
        require(amount > 0, "BlastUP: amount must be gt zero");
        users[msg.sender].claimedAmount += amount;
        token.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
    }

    // Event emitted when a user claims tokens.
    event Claimed(address indexed user, uint256 amount);
}
