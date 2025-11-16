// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LendingPool.sol";
import "../src/MockERC20.sol";
import "./MockPriceFeed.sol";

contract UtilsTest is Test {
    LendingPool pool;
    MockERC20 token;
    MockPriceFeed priceFeed;
    address user = address(0x123);

    function setUp() public {
        pool = new LendingPool();
        token = new MockERC20("TestToken", "TTK");
        priceFeed = new MockPriceFeed(123456789, 8); // price = 1.23456789, decimals = 8
        pool.addSupportedToken(address(token));
    vm.prank(pool.owner());
    pool.setPriceFeed(address(token), address(priceFeed));
    }

    function testSafeTransferFrom() public {
        token.mint(user, 1000e18);
        vm.startPrank(user);
        token.approve(address(pool), 1000e18);
        pool.deposit(address(token), 100e18);
        ```solidity
        // SPDX-License-Identifier: MIT
        pragma solidity ^0.8.28;

        // DEPRECATED: Utility tests referencing pool-specific behavior were removed to focus the
        // repository on P2P lending/borrowing. Keep test scaffolding minimal; add new P2P tests
        // under `test/` when ready.
        ```
        assertEq(normalized, 123456789 * 1e10);
