// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IChainlinkAggregator.sol";

/// @title MockAggregator
/// @author BaseFi P2P Lending Protocol
/// @notice Simple chainlink-like mock aggregator for tests
contract MockAggregator is IChainlinkAggregator {
    /// @notice Number of decimals in the price answer
    uint8 public override decimals;
    int256 private _answer;
    uint256 private _updatedAt;

    /// @notice Constructor to initialize the mock aggregator
    /// @param _decimals Number of decimals for the price feed
    /// @param initialAnswer Initial price answer value
    constructor(uint8 _decimals, int256 initialAnswer) {
        decimals = _decimals;
        _answer = initialAnswer;
        _updatedAt = block.timestamp;
    }

    /// @notice Sets a new price answer for testing
    /// @param a The new price answer value
    function setAnswer(int256 a) external {
        _answer = a;
        _updatedAt = block.timestamp;
    }

    /// @notice Sets the updatedAt timestamp for testing staleness
    /// @param t The timestamp value to set
    function setUpdatedAt(uint256 t) external {
        _updatedAt = t;
    }

    /// @notice Returns the latest round data from the mock price feed
    /// @return roundId The round ID (always 0 in mock)
    /// @return answer The current price answer
    /// @return startedAt The timestamp when the round started (always 0 in mock)
    /// @return updatedAt The timestamp when the answer was last updated
    /// @return answeredInRound The round ID in which the answer was computed (always 0 in mock)
    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _answer, 0, _updatedAt, 0);
    }
}
