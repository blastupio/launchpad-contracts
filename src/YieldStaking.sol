// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ILaunchpad} from "./interfaces/ILaunchpad.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {IERC20Rebasing, YieldMode} from "./interfaces/IERC20Rebasing.sol";
import {IBlast} from "./interfaces/IBlast.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {WadMath} from "./libraries/WadMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

/// @notice Contract keeping collection of staking pools (USDB and WETH only for now).
/// Pools are functioning by tracking "index". It is being set to 1 initially and increases
/// over time when USDB/WETH rewards accrue.
///
/// Each pool tracks totalSupplyScaled which is basically total amount of shares all users
/// deposited into pool have.
///
/// Basically index = tokenBalanceOfThePool / totalSupplyScaled.
///
/// Each user has certain number of pool shares, thus totalSupplyScaled is always equal to the
/// sum of all users shares balances.
///
/// Precision loss might occur during balance accounting via indexes and shares, thus we are also
/// tracking "remainders" for each user. Those remainders are denoted in actual tokens rather than
/// shares and do not accrue yield. This mechanic allows us to ensure that no user funds are lost due
/// to precision while also fairly and correctly distributing rewards through index growth.
///
/// Primary purpose of this contract is to allow users to spend their accrued yield on Launchpad.
/// Users should on;y be able to spend yield and not their direct balance, thus, for each
/// user deposit we are tracking and locking amount which he deposited and only allow withdrawal
/// of additional funds accrued as yield.
contract YieldStaking is OwnableUpgradeable {
    using WadMath for uint256;
    using SafeERC20 for IERC20Rebasing;

    error InvalidPool(address token);

    /* ========== IMMUTABLE VARIABLES ========== */
    ILaunchpad public immutable launchpad;
    IERC20Rebasing public immutable USDB;
    IERC20Rebasing public immutable WETH;
    uint8 public immutable decimalsUSDB;
    IChainlinkOracle public immutable oracle;
    uint8 public immutable oracleDecimals;

    /* ========== STORAGE VARIABLES ========== */
    // Always add to the bottom! Contract is upgradeable

    /// @notice Minimal balance user is required to have after deposit.
    /// Denoted in USDB.
    uint256 public minUSDBStakeValue;

    /// @notice Lock duration after which deposited tokens can be withdrawn.
    uint256 public minTimeToWithdraw;

    struct StakingInfo {
        // Sum of all user.balanceScaled values.
        uint256 totalSupplyScaled;
        // Index of the pool, updated on every rewards claim.
        uint256 lastIndex;
        // State of users deposited into the pool.
        mapping(address => StakingUser) users;
    }

    struct StakingUser {
        // Share of the user in the pool
        uint256 balanceScaled;
        // deposits - withdrawals. Used to track amount which is locked
        // and can only be withdrawn rather than claimed.
        uint256 lockedBalance;
        // Remainders which did not fit into balanceScaled.
        uint256 remainders;
        // The point of time at which user's funds will be unlocked.
        uint256 timestampToWithdraw;
    }

    mapping(address => StakingInfo) public stakingInfos;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _launchpad, address _oracle, address usdb, address weth) {
        launchpad = ILaunchpad(_launchpad);
        USDB = IERC20Rebasing(usdb);
        WETH = IERC20Rebasing(weth);
        decimalsUSDB = IERC20Metadata(usdb).decimals();
        oracle = IChainlinkOracle(_oracle);
        oracleDecimals = oracle.decimals();

        _disableInitializers();
    }

    function initialize(address _owner, address _points, address _pointsOperator) public initializer {
        USDB.configure(YieldMode.CLAIMABLE);
        WETH.configure(YieldMode.CLAIMABLE);
        // initialize pools
        stakingInfos[address(USDB)].lastIndex = WadMath.WAD;
        stakingInfos[address(WETH)].lastIndex = WadMath.WAD;
        IBlastPoints(_points).configurePointsOperator(_pointsOperator);

        __Ownable_init(_owner);
    }

    /* ========== VIEWS ========== */

    function userInfo(address targetToken, address user) external view returns (StakingUser memory) {
        return stakingInfos[targetToken].users[user];
    }

    /// @notice Calculates the next index depending on amounts of rewards accrued.
    function _calculateIndex(uint256 _lastIndex, uint256 scaledSupply, uint256 rewards)
        internal
        pure
        returns (uint256 newIndex)
    {
        if (scaledSupply == 0) {
            return _lastIndex;
        }
        return _lastIndex + rewards.wadDiv(scaledSupply);
    }

    /// @notice Fetches rewards available for claim and calculates the next index for the pool.
    function lastIndex(address targetToken) public view returns (uint256) {
        StakingInfo storage info = stakingInfos[targetToken];
        uint256 rewards = IERC20Rebasing(targetToken).getClaimableAmount(address(this));
        return _calculateIndex(info.lastIndex, info.totalSupplyScaled, rewards);
    }

    function totalSupply(address targetToken) public view returns (uint256) {
        return stakingInfos[targetToken].totalSupplyScaled.wadMul(lastIndex(targetToken));
    }

    /// @notice Calculates total amount of tokens available to a user, including rewards.
    function _getUserBalance(StakingUser memory user, uint256 index) internal pure returns (uint256) {
        return user.balanceScaled.wadMul(index) + user.remainders;
    }

    /// @notice Returns user's balance divided into locked balance which can only be withdrawn
    /// and rewards which can be claimed.
    function balanceAndRewards(address targetToken, address account)
        public
        view
        returns (uint256 balance, uint256 rewards)
    {
        StakingUser memory user = stakingInfos[targetToken].users[account];
        uint256 totalBalance = _getUserBalance(user, lastIndex(targetToken));
        return (user.lockedBalance, totalBalance - user.lockedBalance);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Wraps native ETH into WETH.
    function _wrapETH() internal {
        IWETH(address(WETH)).deposit{value: msg.value}();
    }

    /// @notice Unwraps WETH into ETH.
    function _unwrapETH(uint256 amount) internal {
        IWETH(address(WETH)).withdraw(amount);
    }

    /// @notice Claims all pending rewards and update index.
    function _updateLastIndex(StakingInfo storage info, address token) internal {
        uint256 amount = IERC20Rebasing(token).getClaimableAmount(address(this));
        if (amount > 0) {
            IERC20Rebasing(token).claim(address(this), amount);
            info.lastIndex = _calculateIndex(info.lastIndex, info.totalSupplyScaled, amount);
        }
    }

    /// @notice Main function for altering user's balance. Balance is being divided into
    /// scaled balance (shares) and remainders depending on index.
    function _setBalance(StakingInfo storage info, StakingUser storage user, uint256 newBalance) internal {
        uint256 newBalanceScaled = newBalance.wadDiv(info.lastIndex);

        info.totalSupplyScaled += newBalanceScaled;
        info.totalSupplyScaled -= user.balanceScaled;
        user.balanceScaled = newBalanceScaled;
        user.remainders = newBalance - newBalanceScaled.wadMul(info.lastIndex);
    }

    /// @notice Fetches ETH price from oracle, performing additional safety checks to ensure the oracle is healthy.
    function _getETHPrice() private view returns (uint256) {
        (uint80 roundID, int256 price,, uint256 timestamp, uint80 answeredInRound) = oracle.latestRoundData();

        require(answeredInRound >= roundID, "Stale price");
        require(timestamp != 0, "Round not complete");
        require(price > 0, "Chainlink price reporting 0");

        return uint256(price);
    }

    /// @notice Converts given amount of ETH to USDB, using oracle price
    function _convertETHToUSDB(uint256 volume) private view returns (uint256) {
        // price * volume * real_usdb_decimals / (eth_decimals * oracle_decimals)
        return _getETHPrice() * volume * (10 ** decimalsUSDB) / (10 ** oracleDecimals) / (10 ** 18);
    }

    /// @notice Converts given amount of either WETH or USDB into USDB, using oracle price
    /// for WETH.
    function _convertToUSDB(uint256 volume, address token) internal view returns (uint256) {
        return token != address(USDB) ? _convertETHToUSDB(volume) : volume;
    }

    /* ========== FUNCTIONS ========== */

    function setMinTimeToWithdraw(uint256 _minTimeToWithdraw) external onlyOwner {
        minTimeToWithdraw = _minTimeToWithdraw;
    }

    function setMinUSDBStakeValue(uint256 _minUSDBStakeValue) external onlyOwner {
        minUSDBStakeValue = _minUSDBStakeValue;
    }

    /// @notice Function for staking selected token in the pool.
    /// Updates index and increases user balance.
    /// @param depositToken must be WETH or USDB
    function stake(address depositToken, uint256 amount) external payable {
        if (msg.value > 0) {
            depositToken = address(WETH);
            amount = msg.value;
        }

        StakingInfo storage info = stakingInfos[depositToken];
        StakingUser storage user = info.users[msg.sender];

        if (info.lastIndex == 0) {
            revert InvalidPool(depositToken);
        }
        _updateLastIndex(info, depositToken);

        uint256 newBalance = _getUserBalance(user, info.lastIndex) + amount;
        _setBalance(info, user, newBalance);
        user.lockedBalance += amount;
        user.timestampToWithdraw = block.timestamp + minTimeToWithdraw;

        require(_convertToUSDB(newBalance, depositToken) >= minUSDBStakeValue, "BlastUp: you must send more to stake");

        if (msg.value > 0) {
            _wrapETH();
        } else {
            IERC20Rebasing(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit Staked(depositToken, msg.sender, amount);
    }

    /// @notice Function for claiming accrued rewards.
    /// @param targetToken pool for which rewards are being claimed
    /// @param rewardToken either same as targetToken to get rewards directly, or
    /// a token of the project on Launchpad, to use accrued rewards for purchasing a token
    /// during sale.
    /// @param getETH Flag to unwrap and send native ETH if WETH withdrawal is requested.
    /// @param signature Optional signature for purchasing tokens from sales requiring approval.
    /// @param id Id of the Launchpad sale to spend rewards on.
    function claimReward(
        address targetToken,
        address rewardToken,
        uint256 rewardAmount,
        bool getETH,
        bytes memory signature,
        uint256 id
    ) external {
        StakingInfo storage info = stakingInfos[targetToken];
        StakingUser storage user = info.users[msg.sender];

        if (info.lastIndex == 0) {
            revert InvalidPool(targetToken);
        }
        _updateLastIndex(info, targetToken);

        uint256 balance = _getUserBalance(user, info.lastIndex);

        uint256 claimable = balance - user.lockedBalance;
        require(claimable >= rewardAmount, "BlastUP: you do not have enough rewards");

        _setBalance(info, user, balance - rewardAmount);

        if (rewardToken == targetToken) {
            if (rewardToken == address(WETH) && getETH) {
                _unwrapETH(rewardAmount);
                (bool sent,) = payable(msg.sender).call{value: rewardAmount}("");
                require(sent, "BlastUP: Failed to send Ether");
            } else {
                IERC20Rebasing(rewardToken).safeTransfer(msg.sender, rewardAmount);
            }
            // just send yield
        } else {
            // check allowance
            if (IERC20Rebasing(targetToken).allowance(address(this), address(launchpad)) < rewardAmount) {
                IERC20Rebasing(targetToken).forceApprove(address(launchpad), type(uint256).max);
            }
            uint256 restoredVolume = launchpad.buyTokens(id, targetToken, rewardAmount, msg.sender, signature);
            _setBalance(info, user, _getUserBalance(user, info.lastIndex) + restoredVolume);
        }

        emit RewardClaimed(targetToken, msg.sender, rewardToken, rewardAmount);
    }

    /// @notice Withdraw funds from the pool.
    /// Only balance initially deposited can be withdrawn, all other tokens must be claimed
    /// through claimReward.
    function withdraw(address targetToken, uint256 amount, bool getETH) external {
        StakingInfo storage info = stakingInfos[targetToken];
        StakingUser storage user = info.users[msg.sender];

        if (info.lastIndex == 0) {
            revert InvalidPool(targetToken);
        }

        require(user.timestampToWithdraw <= block.timestamp, "BlastUP: you must wait more time");
        require(amount <= user.lockedBalance, "BlastUP: you do not have enough balance");

        _updateLastIndex(info, targetToken);

        _setBalance(info, user, _getUserBalance(user, info.lastIndex) - amount);
        user.lockedBalance -= amount;

        if (targetToken == address(WETH) && getETH) {
            _unwrapETH(amount);
            (bool sent,) = payable(msg.sender).call{value: amount}("");
            require(sent, "BlastUP: Failed to send Ether");
        } else {
            IERC20Rebasing(targetToken).safeTransfer(msg.sender, amount);
        }

        emit Withdrawn(targetToken, msg.sender, amount);
    }

    receive() external payable {
        require(msg.sender == address(WETH));
    }

    /* ========== EVENTS ========== */

    event Staked(address stakingToken, address indexed user, uint256 amount);
    event Withdrawn(address stakingToken, address indexed user, uint256 amount);
    event RewardClaimed(address stakingToken, address indexed user, address rewardToken, uint256 amountInStakingToken);
}
