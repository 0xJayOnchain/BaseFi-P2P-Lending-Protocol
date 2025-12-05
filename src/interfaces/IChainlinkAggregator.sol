// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IChainlinkAggregator
/// @author BaseFi P2P Lending Protocol
/// @notice Interface for Chainlink price feed aggregators
interface IChainlinkAggregator {
    /// @notice Returns the number of decimals the aggregator responses represent
    /// @return The number of decimals
    function decimals() external view returns (uint8);

    /// @notice Get data about the latest round
    /// @return roundId The round ID
    /// @return answer The price answer
    /// @return startedAt Timestamp when the round started
    /// @return updatedAt Timestamp when the round was updated
    /// @return answeredInRound The round ID in which the answer was computed
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
