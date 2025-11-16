// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {MockPriceFeed} from "./MockPriceFeed.sol";

contract PriceFeedTest is Test {
    LendingPool pool;
    MockERC20 token;
    MockPriceFeed feed;

    function setUp() public {
        pool = new LendingPool();
        token = new MockERC20("T", "T");
        feed = new MockPriceFeed(123456789, 8);

        // register token and feed
        pool.addSupportedToken(address(token));
        pool.setPriceFeed(address(token), address(feed));
    }

    function testGetNormalizedPrice() public {
        // price = 123456789, decimals = 8 -> normalized = 123456789 * 1e10
        uint256 normalized = pool.getNormalizedPrice(address(token));
        assertEq(normalized, uint256(123456789) * (10 ** 10));
    }
}
