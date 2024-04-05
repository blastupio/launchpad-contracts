// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

contract AggregatorV3Mock {
    function latestRoundData()
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, 10 ** 10, 2, 3, 4);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}
