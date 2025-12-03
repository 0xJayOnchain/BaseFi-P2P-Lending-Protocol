// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IChainlinkAggregator.sol";

/// @notice Simple chainlink-like mock aggregator for tests
contract MockAggregator is IChainlinkAggregator {
    uint8 public override decimals;
    int256 private _answer;
    uint256 private _updatedAt;

    constructor(uint8 _decimals, int256 initialAnswer) {
        decimals = _decimals;
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
    }

    function setAnswer(int256 a) external {
        _answer = a;
        _updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 t) external {
        _updatedAt = t;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _answer, 0, _updatedAt, 0);
    }
}
