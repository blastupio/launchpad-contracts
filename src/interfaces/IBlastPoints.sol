// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

interface IBlastPoints {
    function configurePointsOperator(address operator) external;
    function configurePointsOperatorOnBehalf(address contractAddress, address operator) external;
}
