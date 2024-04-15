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
        BEFORE_REGISTARTION,
        REGISTRATION,
        POST_REGISTRATION,
        PUBLIC_SALE,
        FCFS_SALE,
        POST_SALE
    }

    struct PlacedToken {
        uint256 price; // in USDB
        uint256 volumeForYieldStakers;
        uint256 volume;
        uint256 initialVolumeForLowTiers;
        uint256 initialVolumeForHighTiers;
        uint256 lowTiersWeightsSum;
        uint256 highTiersWeightsSum;
        address addressForCollected;
        uint256 registrationStart;
        uint256 registrationEnd;
        uint256 publicSaleStart;
        uint256 fcfsSaleStart;
        uint256 saleEnd;
        uint256 tgeStart;
        uint256 vestingStart;
        uint256 vestingDuration;
        uint8 tokenDecimals;
        uint8 tgePercent;
        bool initialized;
    }

    function userInfo(address token, address user) external view returns (User memory);
    function userAllowedAllocation(address token, address user) external view returns (uint256);
    function getClaimableAmount(address token, address user) external view returns (uint256);
    function getStatus(address token) external view returns (SaleStatus);

    function placeTokens(PlacedToken memory _placedToken, address token) external;

    function register(address token, UserTiers tier, uint256 amountOfTokens, bytes memory signature) external;

    function buyTokens(address token, address paymentContract, uint256 volume, address receiver)
        external
        payable
        returns (uint256);

    function claimTokens(address token) external;
}
