// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV2Router.sol";
import "../src/LendingPool.sol";

/// @title RouterWhitelistTest
/// @author BaseFi
/// @notice Tests router whitelist enforcement and toggling behavior.
contract RouterWhitelistTest is Test {
    /// @notice Event emitted when a router is toggled in the whitelist
    /// @param router The router address
    /// @param whitelisted True if the router is whitelisted
    event RouterWhitelistedSet(address indexed router, bool whitelisted);

    /// @notice Test ERC20 used for fee paths
    MockERC20 internal lendToken;
    /// @notice Mock router used for testing
    MockUniswapV2Router internal router;
    /// @notice Pool under test
    LendingPool internal pool;

    /// @notice Deploy test contracts and setup pool
    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        router = new MockUniswapV2Router();
        pool = new LendingPool(address(0));
    }

    /// @notice claim-and-swap reverts if router is not whitelisted
    function testRevertWhenRouterNotWhitelisted() public {
        // accumulate some owner fees
        pool.setOwnerFeeBPS(1000);
        lendToken.mint(address(this), 100 ether);
        // simulate owner fees
        // directly set state via storage write is not possible; emulate by increasing ownerFees through a small flow
        // simpler: use deal-like setup: transfer tokens to pool and set mapping via internal logic
        // We'll just set mapping through a small loan-less path by calling internal accounting is not available; instead, cheat by writing storage.
        // As Foundry doesn't allow direct mapping writes, mint to borrower and pretend fees exist by using `store` cheatcode.
        // Get slot of ownerFees mapping: depends on contract layout; avoid complex storage ops.
        // Alternate approach: approve and perform a dummy flow to accrue fees requires loan; skip and assert revert occurs before reading amount.

        address[] memory path = new address[](2);
        path[0] = address(lendToken);
        path[1] = address(lendToken);
        vm.expectRevert(bytes("router not whitelisted"));
        pool.claimAndSwapFees(address(router), address(lendToken), path, 0, block.timestamp + 1);
    }

    /// @notice toggling whitelist updates internal state
    function testWhitelistToggleUpdatesState() public {
        pool.setRouterWhitelisted(address(router), true);
        assertTrue(pool.routerWhitelist(address(router)));
        pool.setRouterWhitelisted(address(router), false);
        assertFalse(pool.routerWhitelist(address(router)));
    }
}
