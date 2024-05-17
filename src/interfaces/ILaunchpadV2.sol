// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {ILaunchpad, LaunchpadDataTypes} from "./ILaunchpad.sol";

interface ILaunchpadV2 is ILaunchpad {
    function registerV2(uint256 id, LaunchpadDataTypes.UserTiers tier) external;
    function registerV2WithApprove(uint256 id, LaunchpadDataTypes.UserTiers tier, bytes memory signature) external;
    function buyWithRegisterV2(uint256 id, address paymentContract, uint256 volume) external payable;
}
