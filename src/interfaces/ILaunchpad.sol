// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LaunchpadDataTypes} from "../libraries/LaunchpadDataTypes.sol";

interface ILaunchpad {
    function userInfo(address token, address user) external view returns (LaunchpadDataTypes.User memory);
    function userAllowedAllocation(address token, address user) external view returns (uint256);
    function getClaimableAmount(address token, address user) external view returns (uint256);
    function getStatus(address token) external view returns (LaunchpadDataTypes.SaleStatus);

    function placeTokens(LaunchpadDataTypes.PlacedToken memory _placedToken, address token) external;

    function register(address token, LaunchpadDataTypes.UserTiers tier, uint256 amountOfTokens, bytes memory signature) external;

    function buyTokens(address token, address paymentContract, uint256 volume, address receiver)
        external
        payable
        returns (uint256);

    function claimTokens(address token) external;
}
