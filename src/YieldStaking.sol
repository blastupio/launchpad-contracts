// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILaunchpad} from "./interfaces/ILaunchpad.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {IERC20Rebasing, YieldMode} from "./interfaces/IERC20Rebasing.sol";
import {IBlast} from "./interfaces/IBlast.sol";
import {IWETH} from "./interfaces/IWETH.sol";
import {WadMath} from "./libraries/WadMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract Staking is Ownable {
    using WadMath for uint256;
    using SafeERC20 for IERC20Rebasing;

    error InvalidPool(address token);

    /* ========== STATE VARIABLES ========== */

    ILaunchpad public launchpadAddress;

    IERC20Rebasing public immutable USDB;
    IERC20Rebasing public immutable WETH;
    uint8 public immutable decimalsUSDB;

    IChainlinkOracle public oracle;
    uint8 public oracleDecimals;

    uint256 public minUSDBStakeValue; // in USDB
    uint256 public minTimeToWithdraw;

    IERC20 public immutable BLP;

    // Invariant: amountDeposited <= balanceScaled * lastIndex
    struct StakingUser {
        uint256 balanceScaled;
        uint256 amountDeposited;
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

    constructor(address _launchpadAddress, address blp, address admin, address _oracle, address usdb, address weth)
        Ownable(admin)
    {
        launchpadAddress = ILaunchpad(_launchpadAddress);
        BLP = IERC20(blp);
        USDB = IERC20Rebasing(usdb);
        WETH = IERC20Rebasing(weth);

        oracle = IChainlinkOracle(_oracle);
        oracleDecimals = oracle.decimals();
        decimalsUSDB = IERC20Metadata(address(USDB)).decimals();

        USDB.configure(YieldMode.CLAIMABLE);
        WETH.configure(YieldMode.CLAIMABLE);
        // initialize pools
        stakingInfos[address(USDB)].lastIndex = WadMath.WAD;
        stakingInfos[address(WETH)].lastIndex = WadMath.WAD;
    }

    /* ========== VIEWS ========== */

    function userInfo(address targetToken, address user) external view returns (StakingUser memory) {
        return stakingInfos[targetToken].users[user];
    }

    // function that operates with the lastIndex which will be updated

    function lastIndex(address targetToken) public view returns (uint256) {
        uint256 totalSupplyScaled = stakingInfos[targetToken].totalSupplyScaled;
        return totalSupplyScaled == 0
            ? WadMath.WAD
            : (
                totalSupplyScaled.wadMul(stakingInfos[targetToken].lastIndex)
                    + IERC20Rebasing(targetToken).getClaimableAmount(address(this))
            ).wadDiv(totalSupplyScaled);
    }

    function totalSupply(address targetToken) public view returns (uint256) {
        return stakingInfos[targetToken].totalSupplyScaled.wadMul(lastIndex(targetToken));
    }

    function balanceAndRewards(address targetToken, address account)
        public
        view
        returns (uint256 balance, uint256 rewards)
    {
        StakingUser memory user = stakingInfos[targetToken].users[account];
        balance = user.amountDeposited + user.remainders;
        rewards = _calculateUserRewards(lastIndex(targetToken), user.amountDeposited, user.balanceScaled); 
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
        }

        uint256 supply = info.totalSupplyScaled.wadMul(info.lastIndex);
        if (supply > 0) {
            info.lastIndex = (amount + supply).wadDiv(info.totalSupplyScaled);
        }
    }

    // Decreases user scaled balance, funds lost due to rounding are added to remainders
    function _decreaseBalance(StakingInfo storage info, StakingUser storage user, uint256 amount) internal {
        uint256 scaledBalanceDecrease = amount.wadDivRoundingUp(info.lastIndex);
        info.totalSupplyScaled -= scaledBalanceDecrease;
        user.balanceScaled -= scaledBalanceDecrease;
        user.remainders += scaledBalanceDecrease.wadMul(info.lastIndex) - amount;
    }

    function _calculateUserRewards(uint256 index, uint256 amountDeposited, uint256 balanceScaled) internal pure returns (uint256) {
        uint256 depositedScaled = amountDeposited.wadDivRoundingUp(index);
        uint256 scaledRewards = depositedScaled > balanceScaled ? 0 :balanceScaled - depositedScaled;
        return scaledRewards.wadMul(index);
    }

    function _convertETHToUSDB(uint256 volume) internal view returns (uint256) {
        // price * volume * real_usdb_decimals / (eth_decimals * oracle_decimals)
        (, int256 ans,,,) = oracle.latestRoundData();
        return uint256(ans) * volume * (10 ** decimalsUSDB) / 10 ** oracleDecimals / 10 ** 18;
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
        @param targetToken must be WETH or USDB
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

        uint256 scaledBalanceIncrease = amount.wadDiv(info.lastIndex);
        uint256 depositedIncrease = scaledBalanceIncrease.wadMul(info.lastIndex);
        uint256 remaindersIncrease = amount - depositedIncrease;

        info.totalSupplyScaled += scaledBalanceIncrease;
        user.balanceScaled += scaledBalanceIncrease;
        user.amountDeposited += depositedIncrease;
        user.remainders += remaindersIncrease;
        user.timestampToWithdraw = block.timestamp + minTimeToWithdraw;

        require(
            _convertToUSDB(user.amountDeposited, depositToken) >= minUSDBStakeValue,
            "BlastUp: you must send more to stake"
        );

        if (msg.value == 0) {
            IERC20Rebasing(depositToken).safeTransferFrom(msg.sender, address(this), amount);
        } else {
            _wrapETH();
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

        uint256 totalRewards = _calculateUserRewards(info.lastIndex, user.amountDeposited, user.balanceScaled);
        require(totalRewards >= rewardAmount, "BlastUP: you do not have enough rewards");

        _decreaseBalance(info, user, rewardAmount);

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
            if (IERC20Rebasing(targetToken).allowance(address(this), address(launchpadAddress)) < rewardAmount) {
                IERC20Rebasing(targetToken).forceApprove(address(launchpadAddress), type(uint256).max);
            }
            launchpadAddress.buyTokens(rewardToken, targetToken, rewardAmount, msg.sender);
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
        require(amount <= (user.amountDeposited + user.remainders), "BlastUP: you do not have enough balance");

        _updateLastIndex(info, targetToken);
        uint256 amountFromRemainders = Math.min(user.remainders, amount);
        user.remainders -= amountFromRemainders;
        user.amountDeposited -= amount - amountFromRemainders;
        
        _decreaseBalance(info, user, amount - amountFromRemainders);

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
