// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {ILaunchpad, LaunchpadDataTypes} from "./ILaunchpad.sol";

interface ILaunchpadV2 is ILaunchpad {
    function registerV2(address token, LaunchpadDataTypes.UserTiers tier) external;
    function registerV2WithApprove(address token, LaunchpadDataTypes.UserTiers tier, bytes memory signature) external;
}
