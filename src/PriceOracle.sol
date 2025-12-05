// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./interfaces/IChainlinkAggregator.sol";

/**
 * @title PriceOracle
 * @author BaseFi P2P Lending Protocol
 * @notice Small oracle registry that maps token -> Chainlink-like aggregator and returns normalized prices at 1e18.
 * @dev Small oracle registry that maps token -> Chainlink-like aggregator and returns normalized prices at 1e18.
 */
contract PriceOracle is Ownable {
    /// @notice Mapping of token addresses to their Chainlink price feed aggregators
    mapping(address => address) public priceFeeds;
    /// @notice Maximum allowed age for price data in seconds; 0 means no staleness check
    uint256 public maxPriceAge; // seconds; 0 means no staleness check

    /// @notice Emitted when a price feed is set for a token
    /// @param token The token address
    /// @param aggregator The Chainlink aggregator address
    event PriceFeedSet(address indexed token, address indexed aggregator);
    /// @notice Emitted when the maximum price age is updated
    /// @param oldAge The previous maximum age in seconds
    /// @param newAge The new maximum age in seconds
    event MaxPriceAgeSet(uint256 oldAge, uint256 newAge);

    /// @notice Constructor initializes the oracle with the deployer as owner
    constructor() Ownable(msg.sender) {}

    /// @notice Set the maximum allowed age for price data in seconds; 0 disables staleness check
    /// @param seconds_ The maximum age in seconds (0 to disable staleness checking)
    function setMaxPriceAge(uint256 seconds_) external onlyOwner {
        uint256 old = maxPriceAge;
        maxPriceAge = seconds_;
        emit MaxPriceAgeSet(old, seconds_);
    }

    /// @notice Set the price feed aggregator for a token
    /// @param token The token address
    /// @param aggregator The Chainlink aggregator address for this token
    function setPriceFeed(address token, address aggregator) external onlyOwner {
        priceFeeds[token] = aggregator;
        emit PriceFeedSet(token, aggregator);
    }

    /// @notice Get the price normalized to 1e18
    /// @param token The token address to get the price for
    /// @return The normalized price with 18 decimals
    function getNormalizedPrice(address token) public view returns (uint256) {
        address feed = priceFeeds[token];
        require(feed != address(0), "Price feed not set");
        (, int256 answer,, uint256 updatedAt,) = IChainlinkAggregator(feed).latestRoundData();
        require(answer > 0, "Invalid price");
        if (maxPriceAge > 0) {
            require(updatedAt != 0 && block.timestamp - updatedAt <= maxPriceAge, "stale price");
        }
        uint8 dec = IChainlinkAggregator(feed).decimals();

        if (dec == 18) {
            return uint256(answer);
        } else if (dec < 18) {
            return uint256(answer) * (10 ** (18 - dec));
        } else {
            return uint256(answer) / (10 ** (dec - 18));
        }
    }
}
