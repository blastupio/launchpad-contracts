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

    uint256 public minUSDBStakeValue; // in USDB
    uint256 public minTimeToWithdraw;

    struct StakingUser {
        uint256 balanceScaled;
        // deposits - withdrawals
        uint256 lockedBalance;
        uint256 remainders;
        uint256 timestampToWithdraw;
    }

    struct StakingInfo {
        uint256 totalSupplyScaled;
        uint256 lastIndex;
        mapping(address => StakingUser) users;
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

    function initialize(address _owner, address _points) public initializer {
        USDB.configure(YieldMode.CLAIMABLE);
        WETH.configure(YieldMode.CLAIMABLE);
        // initialize pools
        stakingInfos[address(USDB)].lastIndex = WadMath.WAD;
        stakingInfos[address(WETH)].lastIndex = WadMath.WAD;
        IBlastPoints(_points).configurePointsOperator(_owner);

        __Ownable_init(_owner);
    }

    /* ========== VIEWS ========== */

    function userInfo(address targetToken, address user) external view returns (StakingUser memory) {
        return stakingInfos[targetToken].users[user];
    }

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

    function lastIndex(address targetToken) public view returns (uint256) {
        StakingInfo storage info = stakingInfos[targetToken];
        uint256 rewards = IERC20Rebasing(targetToken).getClaimableAmount(address(this));
        return _calculateIndex(info.lastIndex, info.totalSupplyScaled, rewards);
    }

    function totalSupply(address targetToken) public view returns (uint256) {
        return stakingInfos[targetToken].totalSupplyScaled.wadMul(lastIndex(targetToken));
    }

    function _getUserBalance(StakingUser memory user, uint256 index) internal pure returns (uint256) {
        return user.balanceScaled.wadMul(index) + user.remainders;
    }

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

    function _wrapETH() internal {
        IWETH(address(WETH)).deposit{value: msg.value}();
    }

    function _unwrapETH(uint256 amount) internal {
        IWETH(address(WETH)).withdraw(amount);
    }

    function _updateLastIndex(StakingInfo storage info, address token) internal {
        uint256 amount = IERC20Rebasing(token).getClaimableAmount(address(this));
        if (amount > 0) {
            IERC20Rebasing(token).claim(address(this), amount);
            info.lastIndex = _calculateIndex(info.lastIndex, info.totalSupplyScaled, amount);
        }
    }

    function _setBalance(StakingInfo storage info, StakingUser storage user, uint256 newBalance) internal {
        uint256 newBalanceScaled = newBalance.wadDiv(info.lastIndex);

        info.totalSupplyScaled += newBalanceScaled;
        info.totalSupplyScaled -= user.balanceScaled;
        user.balanceScaled = newBalanceScaled;
        user.remainders = newBalance - newBalanceScaled.wadMul(info.lastIndex);
    }

    function _convertETHToUSDB(uint256 volume) internal view returns (uint256) {
        (, int256 ans,,,) = oracle.latestRoundData();
        return uint256(ans) * volume * (10 ** decimalsUSDB) / (10 ** oracleDecimals) / (10 ** 18);
    }

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

    /*
        @param depositToken must be WETH or USDB
    */
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

    function claimReward(address targetToken, address rewardToken, uint256 rewardAmount, bool getETH) external {
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
            launchpad.buyTokens(rewardToken, targetToken, rewardAmount, msg.sender);
        }

        emit RewardClaimed(targetToken, msg.sender, rewardToken, rewardAmount);
    }

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

    event StakingCreated(address stakingToken);
    event Staked(address stakingToken, address indexed user, uint256 amount);
    event Withdrawn(address stakingToken, address indexed user, uint256 amount);
    event RewardClaimed(address stakingToken, address indexed user, address rewardToken, uint256 amountInStakingToken);
}
