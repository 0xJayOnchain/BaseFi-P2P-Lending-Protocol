// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "./interfaces/IChainlinkAggregator.sol";

/**
 * @title PriceOracle
 * @dev Small oracle registry that maps token -> Chainlink-like aggregator and returns normalized prices at 1e18.
 */
contract PriceOracle is Ownable {
    mapping(address => address) public priceFeeds;
    uint256 public maxPriceAge; // seconds; 0 means no staleness check

    event PriceFeedSet(address indexed token, address indexed aggregator);

    constructor() Ownable(msg.sender) {}

    /// @notice Set the maximum allowed age for price data in seconds; 0 disables staleness check
    function setMaxPriceAge(uint256 seconds_) external onlyOwner {
        maxPriceAge = seconds_;
    }

    function setPriceFeed(address token, address aggregator) external onlyOwner {
        priceFeeds[token] = aggregator;
        emit PriceFeedSet(token, aggregator);
    }

    /// @notice Get the price normalized to 1e18
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
