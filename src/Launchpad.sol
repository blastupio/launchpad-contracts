// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IChainlinkOracle} from "./interfaces/IChainlinkOracle.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ILaunchpad} from "./interfaces/ILaunchpad.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";

contract Launchpad is AccessControlUpgradeable, ILaunchpad {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    error InvalidTokenForBuying(address token);
    error InvalidSaleStatus(address token);

    /* ========== STATE VARIABLES ========== */

    // bytes32 public constant DAO = keccak256("DAO");
    bytes32 public constant OPERATOR = keccak256("OPERATOR");

    IERC20 public USDB;
    IERC20 public WETH;
    uint8 public decimalsUSDB;
    IERC20 public BLP;
    // address public  BLP_STAKING;

    IChainlinkOracle public oracle;
    uint8 public oracleDecimals;

    address public stakingContract;

    address public signer;
    address public admin;

    mapping(address => PlacedToken) public placedTokens;
    mapping(UserTiers => uint256) public minAmountForTier;
    mapping(UserTiers => uint256) public weightForTier;
    mapping(address => mapping(address => User)) public users;

    /* ========== CONSTRUCTOR ========== */

    function initialize(
        address blp,
        address _stakingContract,
        address _oracle,
        address _admin,
        address _signer,
        address usdb,
        address weth
    ) public initializer {
        BLP = IERC20(blp);
        USDB = IERC20(usdb);
        WETH = IERC20(weth);

        signer = _signer;
        stakingContract = _stakingContract;
        oracle = IChainlinkOracle(_oracle);
        oracleDecimals = oracle.decimals();
        decimalsUSDB = IERC20Metadata(address(USDB)).decimals();

        minAmountForTier[UserTiers.BRONZE] = 2_000;
        minAmountForTier[UserTiers.SILVER] = 5_000;
        minAmountForTier[UserTiers.GOLD] = 10_000;
        minAmountForTier[UserTiers.TITANIUM] = 20_000;
        minAmountForTier[UserTiers.PLATINUM] = 50_000;
        minAmountForTier[UserTiers.DIAMOND] = 150_000;

        weightForTier[UserTiers.BRONZE] = 20;
        weightForTier[UserTiers.SILVER] = 30;
        weightForTier[UserTiers.GOLD] = 50;
        weightForTier[UserTiers.TITANIUM] = 10;
        weightForTier[UserTiers.PLATINUM] = 30;
        weightForTier[UserTiers.DIAMOND] = 60;

        admin = _admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(OPERATOR, admin);
    }

    /* ========== VIEWS ========== */

    function userInfo(address token, address user) public view returns (User memory) {
        return users[token][user];
    }

    function getPlacedToken(address token) external view returns (PlacedToken memory) {
        return placedTokens[token];
    }

    function userAllowedAllocation(address token, address user) public view returns (uint256) {
        if (users[token][user].registered) {
            if (placedTokens[token].status == SaleStatus.PUBLIC_SALE) {
                UserTiers tier = users[token][user].tier;
                uint256 weight = weightForTier[tier];
                uint256 boughtAmount = users[token][user].boughtAmount;
                if (users[token][user].tier < UserTiers.TITANIUM) {
                    return weight * placedTokens[token].initialVolumeForLowTiers
                        / placedTokens[token].lowTiersWeightsSum - boughtAmount;
                } else {
                    return weight * placedTokens[token].initialVolumeForHighTiers
                        / placedTokens[token].highTiersWeightsSum - boughtAmount;
                }
            } else if (users[token][user].tier >= UserTiers.TITANIUM) {
                return placedTokens[token].volumeForHighTiers;
            }
        }
        return 0;
    }

    function getClaimableAmount(address token, address user) public view returns (uint256) {
        uint256 tgeAmount = users[token][user].boughtAmount * placedTokens[token].tgePercent / 100;
        uint256 vestedAmount = users[token][user].boughtAmount - tgeAmount;
        uint256 claimedAmount = users[token][user].claimedAmount;

        if (block.timestamp < placedTokens[token].tgeTimestamp) return 0;
        if (block.timestamp < placedTokens[token].vestingStartTimestamp) return tgeAmount - claimedAmount;

        return tgeAmount
            + Math.min(
                vestedAmount * (block.timestamp - placedTokens[token].vestingStartTimestamp)
                    / placedTokens[token].vestingDuration,
                vestedAmount
            ) - claimedAmount;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _convertETHToUSDB(uint256 volume) private view returns (uint256) {
        // price * volume * real_usdb_decimals / (eth_decimals * oracle_decimals)
        (, int256 ans,,,) = oracle.latestRoundData();
        return uint256(ans) * volume * (10 ** decimalsUSDB) / (10 ** oracleDecimals) / (10 ** 18);
    }

    function _convertUSDBToETH(uint256 volume) private view returns (uint256) {
        (, int256 ans,,,) = oracle.latestRoundData();
        return volume * (10 ** 18) * (10 ** oracleDecimals) / (10 ** decimalsUSDB) / uint256(ans);
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

    function _buyTokens(
        PlacedToken storage placedToken,
        User storage user,
        address receiver,
        address token,
        uint256 tokensAmount
    ) internal {
        if (msg.sender != stakingContract) {
            require(msg.sender == receiver, "BlastUP: the receiver must be the sender");
            require(userAllowedAllocation(token, receiver) >= tokensAmount, "BlastUP: You have not enough allocation");

            // Underflow not possible, amount will be set to 0 if not enough
            if (users[token][receiver].tier < UserTiers.TITANIUM) {
                placedToken.volumeForLowTiers -= tokensAmount;
            } else {
                placedToken.volumeForHighTiers -= tokensAmount;
            }
        } else if (placedToken.status == SaleStatus.PUBLIC_SALE) {
            require(tokensAmount <= placedToken.volumeForYieldStakers, "BlastUP: Not enough volume");

            placedToken.volumeForYieldStakers -= tokensAmount;
        } else {
            revert InvalidSaleStatus(token);
        }

        user.boughtAmount += tokensAmount;
    }

    /* ========== FUNCTIONS ========== */

    function setSigner(address _signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        signer = _signer;
    }

    function grantOperatorRole(address _operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(OPERATOR, _operator);
    }

    function revokeOperatorRole(address _operator) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(OPERATOR, _operator);
    }

    function checkOperator(address _operator) external view returns (bool) {
        return hasRole(OPERATOR, _operator);
    }

    function transferAdminRole(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(DEFAULT_ADMIN_ROLE, _admin);
        grantRole(OPERATOR, _admin);
        revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
        revokeRole(OPERATOR, msg.sender);
    }

    function setVestingStartTimestamp(address token, uint256 _vestingStartTimestamp) external onlyRole(OPERATOR) {
        require(placedTokens[token].vestingStartTimestamp > block.timestamp, "BlastUP: vesting already started");
        require(
            _vestingStartTimestamp > block.timestamp && placedTokens[token].currentStateEnd < _vestingStartTimestamp,
            "BlastUP: invalid vesting start timestamp"
        );
        placedTokens[token].vestingStartTimestamp = _vestingStartTimestamp;
    }

    function setTgeTimestamp(address token, uint256 _tgeTimestamp) external onlyRole(OPERATOR) {
        require(placedTokens[token].tgeTimestamp > block.timestamp, "BlastUP: tge already started");
        require(
            _tgeTimestamp > block.timestamp && placedTokens[token].currentStateEnd < _tgeTimestamp,
            "BlastUP: invalid tge timestamp"
        );
        placedTokens[token].tgeTimestamp = _tgeTimestamp;
    }

    function setMinAmountsForTiers(uint256[6] memory amounts) external onlyRole(OPERATOR) {
        minAmountForTier[UserTiers.BRONZE] = amounts[0];
        minAmountForTier[UserTiers.SILVER] = amounts[1];
        minAmountForTier[UserTiers.GOLD] = amounts[2];
        minAmountForTier[UserTiers.TITANIUM] = amounts[3];
        minAmountForTier[UserTiers.PLATINUM] = amounts[4];
        minAmountForTier[UserTiers.DIAMOND] = amounts[5];
    }

    function setWeightsForTiers(uint256[6] memory tiers) external onlyRole(OPERATOR) {
        require(
            tiers[0] + tiers[1] + tiers[2] == 100 && tiers[3] + tiers[4] + tiers[5] == 100, "BlastUP: invalid weights"
        );
        weightForTier[UserTiers.BRONZE] = tiers[0];
        weightForTier[UserTiers.SILVER] = tiers[1];
        weightForTier[UserTiers.GOLD] = tiers[2];
        weightForTier[UserTiers.TITANIUM] = tiers[3];
        weightForTier[UserTiers.PLATINUM] = tiers[4];
        weightForTier[UserTiers.DIAMOND] = tiers[5];
    }

    function placeTokens(PlaceTokensInput memory input) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PlacedToken storage placedToken = placedTokens[input.token];

        require(placedToken.status == SaleStatus.NOT_PLACED, "BlastUP: This token was already placed");

        uint256 sumVolume =
            input.initialVolumeForHighTiers + input.initialVolumeForLowTiers + input.initialVolumeForYieldStakers;
        require(sumVolume > 0, "BlastUP: initial Volume must be > 0");

        uint256 timeOfEndRegistration =
            input.timeOfEndRegistration == 0 ? type(uint256).max : input.timeOfEndRegistration;

        placedToken.price = input.price;

        placedToken.initialVolumeForHighTiers = input.initialVolumeForHighTiers;
        placedToken.volumeForHighTiers = input.initialVolumeForHighTiers;

        placedToken.initialVolumeForLowTiers = input.initialVolumeForLowTiers;
        placedToken.volumeForLowTiers = input.initialVolumeForLowTiers;

        placedToken.volumeForYieldStakers = input.initialVolumeForYieldStakers;

        placedToken.tokenDecimals = IERC20Metadata(input.token).decimals();
        placedToken.addressForCollected = input.addressForCollected;
        placedToken.currentStateEnd = timeOfEndRegistration;
        placedToken.vestingStartTimestamp = type(uint256).max;
        placedToken.tgeTimestamp = type(uint256).max;
        placedToken.vestingDuration = input.vestingDuration;
        placedToken.tgePercent = input.tgePercent;
        placedToken.status = SaleStatus.REGISTRATION;

        IERC20(input.token).safeTransferFrom(msg.sender, address(this), sumVolume);

        emit TokenPlaced(input.token);
    }

    function register(address token, UserTiers tier, uint256 amountOfTokens, bytes memory signature) external {
        PlacedToken storage placedToken = placedTokens[token];
        User storage user = users[token][msg.sender];

        address signer_ = keccak256(abi.encodePacked(msg.sender, amountOfTokens, address(this), block.chainid))
            .toEthSignedMessageHash().recover(signature);

        require(signer_ == signer, "BlastUP: Invalid signature");
        require(placedToken.status == SaleStatus.REGISTRATION, "BlastUP: invalid status");
        require(block.timestamp <= placedToken.currentStateEnd, "BlastUp: registration ended");
        require(!user.registered, "BlastUP: you are already registered");
        require(minAmountForTier[tier] <= amountOfTokens, "BlastUP: you do not have enough BLP tokens for that tier");

        if (tier < UserTiers.TITANIUM) {
            placedToken.lowTiersWeightsSum += weightForTier[tier];
        } else {
            placedToken.highTiersWeightsSum += weightForTier[tier];
        }

        user.tier = tier;
        user.registered = true;

        emit UserRegistered(msg.sender, token, tier);
    }

    function endRegistration(address token) external onlyRole(OPERATOR) {
        PlacedToken storage placedToken = placedTokens[token];

        require(placedToken.status == SaleStatus.REGISTRATION, "BlastUP: invalid status");

        placedToken.status = SaleStatus.POST_REGISTRATION;

        emit RegistrationEnded(token);
    }

    function startPublicSale(address token, uint256 endTimeOfTheRound) external onlyRole(OPERATOR) {
        PlacedToken storage placedToken = placedTokens[token];

        require(placedToken.status == SaleStatus.POST_REGISTRATION, "BlastUp: invalid status");

        if (endTimeOfTheRound == 0) {
            endTimeOfTheRound = type(uint256).max;
        }

        placedToken.status = SaleStatus.PUBLIC_SALE;
        placedToken.currentStateEnd = endTimeOfTheRound;

        emit PublicSaleStarted(token);
    }

    function startFCFSSale(address token, uint256 endTimeOfTheRound) external onlyRole(OPERATOR) {
        PlacedToken storage placedToken = placedTokens[token];

        require(
            placedToken.status == SaleStatus.PUBLIC_SALE || placedToken.status == SaleStatus.POST_REGISTRATION,
            "BlastUp: invalid status"
        );

        if (endTimeOfTheRound == 0) {
            endTimeOfTheRound = type(uint256).max;
        }

        placedToken.status = SaleStatus.FCFS_SALE;
        placedToken.currentStateEnd = endTimeOfTheRound;
        // Add all left volume to high tiers volume as only high tiers are allowed to buy on FCFS rounds
        placedToken.volumeForHighTiers += (placedToken.volumeForLowTiers + placedToken.volumeForYieldStakers);
        placedToken.volumeForLowTiers = 0;
        placedToken.volumeForYieldStakers = 0;

        emit FCFSSaleStarted(token);
    }

    function buyTokens(address token, address paymentContract, uint256 volume, address receiver)
        external
        payable
        returns (uint256)
    {
        PlacedToken storage placedToken = placedTokens[token];
        User storage user = users[token][receiver];

        require(
            placedToken.status == SaleStatus.PUBLIC_SALE || placedToken.status == SaleStatus.FCFS_SALE,
            "BlastUP: invalid status"
        );
        require(block.timestamp < placedToken.currentStateEnd, "BlastUP: round is ended");

        if (msg.value > 0) {
            paymentContract = address(WETH);
            volume = msg.value;
            payable(placedToken.addressForCollected).call{value: msg.value};
        } else {
            require(volume > 0, "BlastUP: volume must be greater than 0");
            require(
                (paymentContract == address(WETH)) || (paymentContract == address(USDB)),
                "BlastUP: incorrect payment contract"
            );
            IERC20(paymentContract).safeTransferFrom(msg.sender, placedToken.addressForCollected, volume);
        }

        uint256 tokensAmount =
            _calculateTokensAmount(volume, paymentContract, placedToken.tokenDecimals, placedToken.price);

        _buyTokens(placedToken, user, receiver, token, tokensAmount);

        emit TokensBought(token, receiver, tokensAmount);

        return tokensAmount;
    }

    function buyTokensByQuantity(address token, address paymentContract, uint256 quantity, address receiver)
        external
        payable
    {
        PlacedToken storage placedToken = placedTokens[token];
        User storage user = users[token][receiver];

        require(
            placedToken.status == SaleStatus.PUBLIC_SALE || placedToken.status == SaleStatus.FCFS_SALE,
            "BlastUP: invalid status"
        );
        require(block.timestamp < placedToken.currentStateEnd, "BlastUP: round is ended");
        require(quantity > 0, "BlastUP: quantitu must be greater than zero");

        uint256 volume = quantity * placedToken.price / (10 ** placedToken.tokenDecimals);

        if (msg.value > 0) {
            paymentContract = address(WETH);
            volume = _convertUSDBToETH(volume);
            if (msg.value > volume) {
                payable(msg.sender).call{value: msg.value - volume};
            }
            payable(placedToken.addressForCollected).call{value: volume};
        } else {
            if (paymentContract == address(WETH)) {
                volume = _convertUSDBToETH(volume);
            } else {
                require(paymentContract == address(USDB));
            }
            IERC20(paymentContract).safeTransferFrom(msg.sender, placedToken.addressForCollected, volume);
        }

        _buyTokens(placedToken, user, receiver, token, quantity);

        emit TokensBought(token, receiver, quantity);
    }

    function endSale(address token) external onlyRole(OPERATOR) {
        PlacedToken storage placedToken = placedTokens[token];

        require(
            placedToken.status == SaleStatus.FCFS_SALE || placedToken.status == SaleStatus.PUBLIC_SALE,
            "BlastUp: invalid status"
        );

        uint256 volume =
            placedToken.volumeForHighTiers + placedToken.volumeForLowTiers + placedToken.volumeForYieldStakers;

        placedToken.status = SaleStatus.POST_SALE;
        placedToken.volumeForHighTiers = 0;
        placedToken.volumeForLowTiers = 0;
        placedToken.volumeForYieldStakers = 0;
        // transfer remaining tokens to the DAO address
        IERC20(token).safeTransfer(admin, volume);

        emit SaleEnded(token);
    }

    function claimTokens(address token) external {
        User storage user = users[token][msg.sender];

        uint256 claimableAmount = getClaimableAmount(token, msg.sender);

        require(claimableAmount > 0, "BlastUP: you have not enough claimable tokens");

        user.claimedAmount += claimableAmount;
        IERC20(token).safeTransfer(msg.sender, claimableAmount);

        emit TokensClaimed(token, msg.sender);
    }

    /* ========== EVENTS ========== */
    event TokenPlaced(address token);
    event UserRegistered(address indexed user, address indexed token, UserTiers tier);
    event RegistrationEnded(address token);
    event TokensBought(address indexed token, address indexed buyer, uint256 amount);
    event PublicSaleStarted(address token);
    event FCFSSaleStarted(address token);
    event SaleEnded(address token);
    event TokensClaimed(address token, address user);
}
