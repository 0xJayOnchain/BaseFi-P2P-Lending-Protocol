// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/PriceOracle.sol";
import "../src/mocks/MockAggregator.sol";
import "../src/mocks/MockERC20.sol";

contract PriceOracleStalenessTest is Test {
    PriceOracle oracle;
    MockAggregator agg;
    MockERC20 token;

    function setUp() public {
        oracle = new PriceOracle();
        token = new MockERC20("T", "TKN", 18);
        // aggregator with 18 decimals and initial 1e18
        agg = new MockAggregator(18, int256(1e18));
        oracle.setPriceFeed(address(token), address(agg));
    }

    function testFreshPricePasses() public {
        oracle.setMaxPriceAge(1 days);
        uint256 p = oracle.getNormalizedPrice(address(token));
        assertEq(p, 1e18);
    }

    function testStalePriceReverts() public {
        oracle.setMaxPriceAge(1 days);
        // simulate stale feed by setting aggregator updatedAt to a time older than maxPriceAge
        agg.setUpdatedAt(block.timestamp);
        // advance time beyond max age
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(bytes("stale price"));
        oracle.getNormalizedPrice(address(token));
    }
}
