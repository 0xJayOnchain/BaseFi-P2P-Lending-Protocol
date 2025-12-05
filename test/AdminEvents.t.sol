// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/LendingPool.sol";

/// @title AdminEventsTest
/// @author BaseFi
/// @notice Tests that admin setter functions update state as expected.
contract AdminEventsTest is Test {
    /// @notice LendingPool under test
    LendingPool internal pool;
    // re-declare events for matching

    /// @notice Event emitted when owner fee basis points are updated
    /// @param oldBps The previous owner fee in basis points
    /// @param newBps The new owner fee in basis points
    event OwnerFeeBpsUpdated(uint256 oldBps, uint256 newBps);
    /// @notice Event emitted when penalty basis points are updated
    /// @param oldBps The previous penalty in basis points
    /// @param newBps The new penalty in basis points
    event PenaltyBpsUpdated(uint256 oldBps, uint256 newBps);

    /// @notice Deploy a fresh pool before each test
    function setUp() public {
        pool = new LendingPool(address(0));
    }

    /// @notice Owner fee BPS can be set and read back
    function testOwnerFeeBpsUpdated() public {
        pool.setOwnerFeeBPS(500);
        assertEq(pool.ownerFeeBPS(), 500);
    }

    /// @notice Penalty BPS can be set and read back
    function testPenaltyBpsUpdated() public {
        pool.setPenaltyBPS(300);
        assertEq(pool.penaltyBPS(), 300);
    }
}
