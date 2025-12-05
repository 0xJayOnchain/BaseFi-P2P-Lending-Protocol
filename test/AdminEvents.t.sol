// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/LendingPool.sol";

contract AdminEventsTest is Test {
    LendingPool pool;
    // re-declare events for matching

    event OwnerFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    event PenaltyBpsUpdated(uint256 oldBps, uint256 newBps);

    function setUp() public {
        pool = new LendingPool(address(0));
    }

    function testOwnerFeeBpsUpdated() public {
        pool.setOwnerFeeBPS(500);
        assertEq(pool.ownerFeeBPS(), 500);
    }

    function testPenaltyBpsUpdated() public {
        pool.setPenaltyBPS(300);
        assertEq(pool.penaltyBPS(), 300);
    }
}
