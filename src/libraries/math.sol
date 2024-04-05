// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library WadRayMath {
    uint256 internal constant WAD = 1e18;

    function wadMul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b / WAD;
    }

    function wadDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * WAD / b;
    }

    function wadDivRoundingUp(uint256 a, uint256 b) internal pure returns (uint256) {
        return Math.mulDiv(a, WAD, b, Math.Rounding.Ceil);
    }
}
