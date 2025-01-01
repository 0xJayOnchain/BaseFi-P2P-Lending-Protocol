// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;
    MockERC20 public token1;
    MockERC20 public token2;
    address public owner;
    address public user1;
    address public user2;

    // Test constants
    uint256 constant INITIAL_BALANCE = 1000e18;
    uint256 constant DEPOSIT_AMOUNT = 100e18;
    uint256 constant BORROW_AMOUNT = 50e18;
    uint256 constant COLLATERAL_AMOUNT = 150e18;

    function setUp() public {
        // Deploy contracts
        pool = new LendingPool();
        token1 = new MockERC20("Token1", "TK1");
        token2 = new MockERC20("Token2", "TK2");

        // Setup accounts
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Add supported tokens
        pool.addSupportedToken(address(token1));
        pool.addSupportedToken(address(token2));

        // Mint tokens to users
        token1.mint(user1, INITIAL_BALANCE);
        token1.mint(user2, INITIAL_BALANCE);
        token2.mint(user1, INITIAL_BALANCE);
        token2.mint(user2, INITIAL_BALANCE);

        // Approve spending
        vm.startPrank(user1);
        token1.approve(address(pool), type(uint256).max);
        token2.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token1.approve(address(pool), type(uint256).max);
        token2.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    // Test adding supported tokens
    function testAddSupportedToken() public {
        address newToken = makeAddr("newToken");
        pool.addSupportedToken(newToken);
        assertTrue(pool.supportedTokens(newToken));
    }

    // Test deposits
    function testDeposit() public {
        vm.startPrank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);

        (uint256 amount, uint256 timestamp, uint256 rate) = pool.lendingPositions(address(token1), user1);
        // Verify the deposited amount minus the owner fee
        assertEq(amount, DEPOSIT_AMOUNT - pool.calculateOwnerFee(DEPOSIT_AMOUNT));

        // Verify the timestamp matches when we made the deposit
        assertEq(timestamp, block.timestamp);

        // Verify an interest rate was set (just checking it's > 0)
        assertGt(rate, 0);

        vm.stopPrank(); // Stop acting as user1
    }
}
