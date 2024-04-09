// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ILaunchpad {
    enum UserTiers {
        BRONZE,
        SILVER,
        GOLD,
        TITANIUM,
        PLATINUM,
        DIAMOND
    }

    struct User {
        uint256 claimedAmount;
        uint256 boughtAmount;
        UserTiers tier;
        bool registered;
    }

    enum SaleStatus {
        NOT_PLACED,
        REGISTRATION,
        POST_REGISTRATION,
        PUBLIC_SALE,
        FCFS_SALE,
        POST_SALE
    }

    struct PlacedToken {
        uint256 price; // in USDB
        uint256 volumeForYieldStakers;
        uint256 volumeForLowTiers;
        uint256 volumeForHighTiers;
        uint256 initialVolumeForLowTiers;
        uint256 initialVolumeForHighTiers;
        uint256 lowTiersWeightsSum;
        uint256 highTiersWeightsSum;
        uint8 tokenDecimals;
        address addressForCollected;
        SaleStatus status;
        uint256 currentStateEnd;
        uint256 vestingStartTimestamp; // or cliff end
        uint256 vestingDuration;
        uint256 tgeTimestamp;
        uint8 tgePercent;
    }

    struct PlaceTokensInput {
        uint256 price;
        address token;
        uint256 initialVolumeForHighTiers;
        uint256 initialVolumeForLowTiers;
        uint256 initialVolumeForYieldStakers;
        uint256 timeOfEndRegistration;
        address addressForCollected;
        uint256 vestingDuration;
        uint8 tgePercent;
    }

    function userInfo(address token, address user) external view returns (User memory);
    function userAllowedAllocation(address token, address user) external view returns (uint256);
    function getClaimableAmount(address token, address user) external view returns (uint256);

    function placeTokens(PlaceTokensInput memory input) external;

    function register(address token, UserTiers tier, uint256 amountOfTokens, bytes memory signature) external;

    function buyTokens(address token, address paymentContract, uint256 volume, address receiver)
        external
        payable
        returns (uint256);

    function buyTokensByQuantity(address token, address paymentContract, uint256 quantity, address receiver)
        external
        payable;

    function claimTokens(address token) external;
}
