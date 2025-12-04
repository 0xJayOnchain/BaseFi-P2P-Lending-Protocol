// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/PriceOracle.sol";
import "../src/mocks/MockAggregator.sol";

contract PriceOracleTest is Test {
    // re-declare events for matching
    event PriceFeedSet(address indexed token, address indexed aggregator);
    event MaxPriceAgeSet(uint256 oldAge, uint256 newAge);
    PriceOracle oracle;
    MockAggregator feed;
    address token = address(0x123);

    function setUp() public {
        oracle = new PriceOracle();
        // this test contract is the owner of the oracle
        feed = new MockAggregator(8, int256(2000 * 10 ** 8)); // price = 2000 (8 decimals)
    vm.expectEmit(true, true, false, true);
    emit PriceFeedSet(token, address(feed));
        oracle.setPriceFeed(token, address(feed));
    }

    function testGetNormalizedPrice() public {
        uint256 p = oracle.getNormalizedPrice(token);
        assertEq(p, 2000 * 1e18);

        // change price
        feed.setAnswer(int256(1500 * 10 ** 8));
        uint256 p2 = oracle.getNormalizedPrice(token);
        assertEq(p2, 1500 * 1e18);
    }

    function testSetMaxPriceAgeEmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit MaxPriceAgeSet(0, 1 days);
        oracle.setMaxPriceAge(1 days);
        assertEq(oracle.maxPriceAge(), 1 days);
    }
}
