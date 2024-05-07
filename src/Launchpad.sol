// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ILaunchpad, LaunchpadDataTypes as Types} from "./interfaces/ILaunchpad.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IBlastPoints} from "./interfaces/IBlastPoints.sol";

contract Launchpad is OwnableUpgradeable, ILaunchpad {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidSaleStatus(uint256 id);

    /* ========== IMMUTABLE VARIABLES ========== */
    address public immutable yieldStaking;
    IERC20 public immutable USDB;
    IERC20 public immutable WETH;
    uint8 public immutable decimalsUSDB;
    IChainlinkOracle public immutable oracle;
    uint8 public immutable oracleDecimals;

    /* ========== STORAGE VARIABLES =========== */
    // Always add to the bottom! Contract is upgradeable

    address public signer;
    address public operator;

    Types.PlacedToken[] public placedTokens;

    mapping(Types.UserTiers => uint256) public minAmountForTier;
    mapping(Types.UserTiers => uint256) public weightForTier;
    mapping(uint256 => mapping(address => Types.User)) public users;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _weth, address _usdb, address _oracle, address _yieldStaking) {
        WETH = IERC20(_weth);
        USDB = IERC20(_usdb);
        decimalsUSDB = IERC20Metadata(address(USDB)).decimals();
        oracle = IChainlinkOracle(_oracle);
        oracleDecimals = oracle.decimals();
        yieldStaking = _yieldStaking;

        _disableInitializers();
    }

    function initialize(address _owner, address _signer, address _operator, address _points, address _pointsOperator)
        public
        initializer
    {
        signer = _signer;
        operator = _operator;
        IBlastPoints(_points).configurePointsOperator(_pointsOperator);

        minAmountForTier[Types.UserTiers.BRONZE] = 2_000;
        minAmountForTier[Types.UserTiers.SILVER] = 5_000;
        minAmountForTier[Types.UserTiers.GOLD] = 10_000;
        minAmountForTier[Types.UserTiers.TITANIUM] = 20_000;
        minAmountForTier[Types.UserTiers.PLATINUM] = 50_000;
        minAmountForTier[Types.UserTiers.DIAMOND] = 150_000;

        weightForTier[Types.UserTiers.BRONZE] = 20;
        weightForTier[Types.UserTiers.SILVER] = 30;
        weightForTier[Types.UserTiers.GOLD] = 50;
        weightForTier[Types.UserTiers.TITANIUM] = 10;
        weightForTier[Types.UserTiers.PLATINUM] = 30;
        weightForTier[Types.UserTiers.DIAMOND] = 60;

        __Ownable_init(_owner);
    }

    /* ========== VIEWS ========== */

    function userInfo(uint256 id, address user) public view returns (Types.User memory) {
        return users[id][user];
    }

    function getPlacedToken(uint256 id) external view returns (Types.PlacedToken memory) {
        return placedTokens[id];
    }

    function getStatus(uint256 id) public view returns (Types.SaleStatus) {
        if (placedTokens.length <= id) return Types.SaleStatus.NOT_PLACED;
        if (placedTokens[id].registrationStart > block.timestamp) return Types.SaleStatus.BEFORE_REGISTARTION;
        if (placedTokens[id].registrationEnd > block.timestamp) return Types.SaleStatus.REGISTRATION;
        if (placedTokens[id].publicSaleStart > block.timestamp) return Types.SaleStatus.POST_REGISTRATION;
        if (placedTokens[id].fcfsSaleStart > block.timestamp) return Types.SaleStatus.PUBLIC_SALE;
        if (placedTokens[id].saleEnd > block.timestamp) return Types.SaleStatus.FCFS_SALE;
        return Types.SaleStatus.POST_SALE;
    }

    function userAllowedAllocation(uint256 id, address user) public view returns (uint256) {
        if (!users[id][user].registered) return 0;
        if (getStatus(id) == Types.SaleStatus.PUBLIC_SALE) {
            Types.UserTiers tier = users[id][user].tier;
            uint256 weight = weightForTier[tier];
            uint256 boughtAmount = users[id][user].boughtPublicSale;
            if (users[id][user].tier < Types.UserTiers.TITANIUM) {
                return weight * placedTokens[id].initialVolumeForLowTiers / placedTokens[id].lowTiersWeightsSum
                    - boughtAmount;
            } else {
                return weight * placedTokens[id].initialVolumeForHighTiers / placedTokens[id].highTiersWeightsSum
                    - boughtAmount;
            }
        } else if (users[id][user].tier >= Types.UserTiers.TITANIUM) {
            return placedTokens[id].volume;
        } else {
            return 0;
        }
    }

    function getClaimableAmount(uint256 id, address user) public view returns (uint256) {
        uint256 tgeAmount = users[id][user].boughtAmount * placedTokens[id].tgePercent / 100;
        uint256 vestedAmount = users[id][user].boughtAmount - tgeAmount;
        uint256 claimedAmount = users[id][user].claimedAmount;

        if (block.timestamp < placedTokens[id].tgeStart) return 0;
        if (block.timestamp < placedTokens[id].vestingStart) return tgeAmount - claimedAmount;

        return tgeAmount
            + Math.min(
                vestedAmount * (block.timestamp - placedTokens[id].vestingStart) / placedTokens[id].vestingDuration,
                vestedAmount
            ) - claimedAmount;
    }

    modifier onlyOperatorOrOwner() {
        require(msg.sender == operator || msg.sender == owner(), "BlastUP: caller is not the operator");
        _;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _convertETHToUSDB(uint256 volume) private view returns (uint256) {
        // price * volume * real_usdb_decimals / (eth_decimals * oracle_decimals)
        (, int256 ans,,,) = oracle.latestRoundData();
        return uint256(ans) * volume * (10 ** decimalsUSDB) / (10 ** oracleDecimals) / (10 ** 18);
    }

    function _calculateTokensAmount(uint256 volume, address paymentContract, uint8 decimals, uint256 price)
        private
        view
        returns (uint256)
    {
        if (paymentContract == address(WETH)) {
            volume = _convertETHToUSDB(volume);
        }

        uint256 tokensAmount = (volume * (10 ** decimals)) / price;

        require(tokensAmount > 0, "BlastUP: you can not buy zero tokens");

        return tokensAmount;
    }

    function _register(uint256 amountOfTokens, uint256 id, Types.UserTiers tier) internal {
        Types.PlacedToken storage placedToken = placedTokens[id];
        Types.User storage user = users[id][msg.sender];

        require(getStatus(id) == Types.SaleStatus.REGISTRATION, "BlastUP: invalid status");
        require(!user.registered, "BlastUP: you are already registered");
        require(minAmountForTier[tier] <= amountOfTokens, "BlastUP: you do not have enough BLP tokens for that tier");

        if (tier < Types.UserTiers.TITANIUM) {
            placedToken.lowTiersWeightsSum += weightForTier[tier];
        } else {
            placedToken.highTiersWeightsSum += weightForTier[tier];
        }

        user.tier = tier;
        user.registered = true;

        emit UserRegistered(msg.sender, placedToken.token, id, tier);
    }

    function _validateUserBalanceSignature(uint256 amountOfTokens, bytes memory signature) internal view {
        address signer_ = keccak256(abi.encodePacked(msg.sender, amountOfTokens, address(this), block.chainid))
            .toEthSignedMessageHash().recover(signature);
        require(signer_ == signer, "BlastUP: Invalid signature");
    }

    function _validateApproveSignature(address user, uint256 id, bytes memory signature) internal view {
        address signer_ = keccak256(abi.encodePacked(user, id, address(this), block.chainid)).toEthSignedMessageHash()
            .recover(signature);
        require(signer_ == signer, "BlastUP: Invalid signature");
    }

    /* ========== FUNCTIONS ========== */

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    function setOperator(address _operator) external onlyOwner {
        operator = _operator;
    }

    function setMinAmountsForTiers(uint256[6] memory amounts) external onlyOperatorOrOwner {
        minAmountForTier[Types.UserTiers.BRONZE] = amounts[0];
        minAmountForTier[Types.UserTiers.SILVER] = amounts[1];
        minAmountForTier[Types.UserTiers.GOLD] = amounts[2];
        minAmountForTier[Types.UserTiers.TITANIUM] = amounts[3];
        minAmountForTier[Types.UserTiers.PLATINUM] = amounts[4];
        minAmountForTier[Types.UserTiers.DIAMOND] = amounts[5];
    }

    function setWeightsForTiers(uint256[6] memory weights) external onlyOperatorOrOwner {
        weightForTier[Types.UserTiers.BRONZE] = weights[0];
        weightForTier[Types.UserTiers.SILVER] = weights[1];
        weightForTier[Types.UserTiers.GOLD] = weights[2];
        weightForTier[Types.UserTiers.TITANIUM] = weights[3];
        weightForTier[Types.UserTiers.PLATINUM] = weights[4];
        weightForTier[Types.UserTiers.DIAMOND] = weights[5];
    }

    function setRegistrationStart(uint256 id, uint256 _registrationStart) external onlyOperatorOrOwner {
        require(_registrationStart > block.timestamp, "BlastUP: invalid registartion start timestamp");
        placedTokens[id].registrationStart = _registrationStart;
    }

    function setRegistrationEnd(uint256 id, uint256 _registrationEnd) external onlyOperatorOrOwner {
        require(_registrationEnd > block.timestamp, "BlastUP: invalid registartion end timestamp");
        placedTokens[id].registrationEnd = _registrationEnd;
    }

    function setPublicSaleStart(uint256 id, uint256 _publicSaleStart) external onlyOperatorOrOwner {
        require(_publicSaleStart > block.timestamp, "BlastUP: invalid public sale start timestamp");
        placedTokens[id].publicSaleStart = _publicSaleStart;
    }

    function setFCFSSaleStart(uint256 id, uint256 _fcfsSaleStart) external onlyOperatorOrOwner {
        require(_fcfsSaleStart > block.timestamp, "BlastUP: invalid fcfs start timestamp");
        placedTokens[id].fcfsSaleStart = _fcfsSaleStart;
    }

    function setSaleEnd(uint256 id, uint256 _saleEnd) external onlyOperatorOrOwner {
        require(_saleEnd > block.timestamp, "BlastUP: invalid sale end timestamp");
        placedTokens[id].saleEnd = _saleEnd;
    }

    function setTgeStart(uint256 id, uint256 _tgeStart) external onlyOperatorOrOwner {
        require(_tgeStart > block.timestamp, "BlastUP: invalid tge timestamp");
        placedTokens[id].tgeStart = _tgeStart;
    }

    function setVestingStart(uint256 id, uint256 _vestingStart) external onlyOperatorOrOwner {
        require(_vestingStart > block.timestamp, "BlastUP: invalid vesting start timestamp");
        placedTokens[id].vestingStart = _vestingStart;
    }

    function placeTokens(Types.PlacedToken memory _placedToken) external onlyOwner {
        uint256 id = placedTokens.length;
        uint256 sumVolume = _placedToken.initialVolumeForHighTiers + _placedToken.initialVolumeForLowTiers
            + _placedToken.volumeForYieldStakers;
        require(sumVolume > 0, "BlastUP: initial Volume must be > 0");
        require(
            _placedToken.tokenDecimals == IERC20Metadata(_placedToken.token).decimals(), "BlastUP: invalid decimals"
        );
        require(
            _placedToken.registrationStart > block.timestamp
                && _placedToken.registrationEnd > _placedToken.registrationStart
                && _placedToken.publicSaleStart > _placedToken.registrationEnd
                && _placedToken.fcfsSaleStart > _placedToken.publicSaleStart
                && _placedToken.saleEnd > _placedToken.fcfsSaleStart && _placedToken.tgeStart > _placedToken.saleEnd
                && _placedToken.vestingStart > _placedToken.tgeStart,
            "BlastUP: invalid timestamps"
        );
        require(_placedToken.volume == sumVolume, "BlastUP: sum of initial volumes must be equal to volume param");

        placedTokens.push(_placedToken);

        IERC20(_placedToken.token).safeTransferFrom(msg.sender, address(this), sumVolume);

        emit TokenPlaced(_placedToken.token, id);
    }

    function register(uint256 id, Types.UserTiers tier, uint256 amountOfTokens, bytes memory signature)
        external
        virtual
    {
        require(!placedTokens[id].approved, "BlastUP: you need to use register with approve function");
        _validateUserBalanceSignature(amountOfTokens, signature);
        _register(amountOfTokens, id, tier);
    }

    function registerWithApprove(
        uint256 id,
        Types.UserTiers tier,
        uint256 amountOfTokens,
        bytes memory signature,
        bytes memory approveSignature
    ) external virtual {
        _validateApproveSignature(msg.sender, id, approveSignature);
        _validateUserBalanceSignature(amountOfTokens, signature);
        _register(amountOfTokens, id, tier);
    }

    function buyTokens(uint256 id, address paymentContract, uint256 volume, address receiver, bytes memory signature)
        external
        payable
        virtual
        returns (uint256)
    {
        Types.PlacedToken storage placedToken = placedTokens[id];
        Types.User storage user = users[id][receiver];
        Types.SaleStatus status = getStatus(id);

        require(
            status == Types.SaleStatus.PUBLIC_SALE || status == Types.SaleStatus.FCFS_SALE, "BlastUP: invalid status"
        );

        if (msg.value > 0) {
            paymentContract = address(WETH);
            volume = msg.value;
        } else {
            require(volume > 0, "BlastUP: volume must be greater than 0");
            require(
                (paymentContract == address(WETH)) || (paymentContract == address(USDB)),
                "BlastUP: incorrect payment contract"
            );
        }

        uint256 tokensAmount =
            _calculateTokensAmount(volume, paymentContract, placedToken.tokenDecimals, placedToken.price);

        if (msg.sender != yieldStaking) {
            require(msg.sender == receiver, "BlastUP: the receiver must be the sender");
            require(userAllowedAllocation(id, msg.sender) >= tokensAmount, "BlastUP: You have not enough allocation");
            if (status == Types.SaleStatus.PUBLIC_SALE) {
                user.boughtPublicSale += tokensAmount;
            }
        } else if (status == Types.SaleStatus.PUBLIC_SALE) {
            require(tokensAmount <= placedToken.volumeForYieldStakers, "BlastUP: Not enough volume");
            if (placedToken.approved) {
                _validateApproveSignature(receiver, id, signature);
            }
            placedToken.volumeForYieldStakers -= tokensAmount;
        } else {
            revert("Invalid sale status");
        }

        user.boughtAmount += tokensAmount;
        placedToken.volume -= tokensAmount;

        if (msg.value > 0) {
            (bool success,) = payable(placedToken.addressForCollected).call{value: msg.value}("");
            require(success, "BlastUP: failed to send ETH");
        } else {
            IERC20(paymentContract).safeTransferFrom(msg.sender, placedToken.addressForCollected, volume);
        }

        emit TokensBought(placedToken.token, receiver, id, tokensAmount);

        return tokensAmount;
    }

    function claimRemainders(uint256 id) external onlyOperatorOrOwner {
        Types.PlacedToken storage placedToken = placedTokens[id];

        require(getStatus(id) == Types.SaleStatus.POST_SALE, "BlastUP: invalid status");

        uint256 volume = placedToken.volume;

        placedToken.volume = 0;
        placedToken.volumeForYieldStakers = 0;
        // transfer remaining tokens to the DAO address
        IERC20(placedToken.token).safeTransfer(owner(), volume);
    }

    function claimTokens(uint256 id) external {
        Types.PlacedToken storage placedToken = placedTokens[id];
        Types.User storage user = users[id][msg.sender];

        uint256 claimableAmount = getClaimableAmount(id, msg.sender);

        require(claimableAmount > 0, "BlastUP: you have not enough claimable tokens");

        user.claimedAmount += claimableAmount;
        IERC20(placedToken.token).safeTransfer(msg.sender, claimableAmount);

        emit TokensClaimed(placedToken.token, id, msg.sender);
    }

    /* ========== EVENTS ========== */
    event TokenPlaced(address indexed token, uint256 id);
    event UserRegistered(address indexed user, address indexed token, uint256 id, Types.UserTiers tier);
    event TokensBought(address indexed token, address indexed buyer, uint256 id, uint256 amount);
    event TokensClaimed(address indexed token, uint256 id, address user);
}
