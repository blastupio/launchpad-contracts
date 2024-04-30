// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {LaunchpadDataTypes} from "../libraries/LaunchpadDataTypes.sol";

interface ILaunchpad {
    function userInfo(uint256 id, address user) external view returns (LaunchpadDataTypes.User memory);
    function userAllowedAllocation(uint256 id, address user) external view returns (uint256);
    function getClaimableAmount(uint256 id, address user) external view returns (uint256);
    function getStatus(uint256 id) external view returns (LaunchpadDataTypes.SaleStatus);

    function placeTokens(LaunchpadDataTypes.PlacedToken memory _placedToken) external;

    function register(uint256 id, LaunchpadDataTypes.UserTiers tier, uint256 amountOfTokens, bytes memory signature)
        external;

    function registerWithApprove(
        uint256 id,
        LaunchpadDataTypes.UserTiers tier,
        uint256 amountOfTokens,
        bytes memory signature,
        bytes memory approveSignature
    ) external;

    function buyTokens(uint256 id, address paymentContract, uint256 volume, address receiver, bytes memory signature)
        external
        payable
        returns (uint256);

    function claimTokens(uint256 id) external;
}
