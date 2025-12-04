// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV2Router.sol";
import "../src/LendingPool.sol";

contract RouterWhitelistTest is Test {
    // re-declare event for matching
    event RouterWhitelistedSet(address indexed router, bool whitelisted);
    MockERC20 lendToken;
    MockUniswapV2Router router;
    LendingPool pool;

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        router = new MockUniswapV2Router();
        pool = new LendingPool(address(0));
    }

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

    function testWhitelistEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit RouterWhitelistedSet(address(router), true);
        pool.setRouterWhitelisted(address(router), true);

        // flip back to false
        vm.expectEmit(true, false, false, true);
        emit RouterWhitelistedSet(address(router), false);
        pool.setRouterWhitelisted(address(router), false);
    }
}
