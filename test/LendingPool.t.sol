// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "../src/LendingPool.sol";

contract LendingPoolTest is Test {
    LendingPool public lendingPool;

    address baseEthTokenAddress = 0x4200000000000000000000000000000000000006;

    function setUp() public {
        lendingPool = new LendingPool();
    }

    function testAddSupportedToken() public {
        // Add a supported token
        lendingPool.addSupportedToken(baseEthTokenAddress);

          // Read the mapping to check if the token is supported
        bool isSupported = lendingPool.supportedTokens(baseEthTokenAddress);
        
        // Assert that the token is supported
        assertTrue(isSupported, "The token should be supported.");
    }
}
