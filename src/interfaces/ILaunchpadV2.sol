// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILaunchpad, LaunchpadDataTypes} from "./ILaunchpad.sol";

interface ILaunchpadV2 is ILaunchpad {
    function registerV2(address token, LaunchpadDataTypes.UserTiers tier) external;
}
