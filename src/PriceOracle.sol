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

    event PriceFeedSet(address indexed token, address indexed aggregator);

    constructor() Ownable(msg.sender) {}

    function setPriceFeed(address token, address aggregator) external onlyOwner {
        priceFeeds[token] = aggregator;
        emit PriceFeedSet(token, aggregator);
    }

    /// @notice Get the price normalized to 1e18
    function getNormalizedPrice(address token) public view returns (uint256) {
        address feed = priceFeeds[token];
        require(feed != address(0), "Price feed not set");
        (, int256 answer,,,) = IChainlinkAggregator(feed).latestRoundData();
        require(answer > 0, "Invalid price");
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
