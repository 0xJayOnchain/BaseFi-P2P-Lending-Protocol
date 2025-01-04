// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console2, console} from "forge-std/Test.sol";
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

    // Different fee percentages
    // Math precision tests
    function testCalculateOwnerFee() public {
        uint256 amount = 1000e18;
        uint256 expectedFee = (amount * pool.OWNER_FEE_BPS()) / 10000;
        assertEq(pool.calculateOwnerFee(amount), expectedFee);
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

        // Verify an interest rate was set (just checking it's > 0 for now. Needs to be updated.)
        assertGt(rate, 0);

        vm.stopPrank();
    }

    // Test borrow
    function testBorrow() public {
        uint256 fundsBefore = token1.balanceOf(user2);
        // Make intial deposit
        vm.startPrank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);
        vm.stopPrank();

        // Borrow from deposited funds
        vm.startPrank(user2);
        pool.borrow(address(token1), BORROW_AMOUNT, address(token2), COLLATERAL_AMOUNT);
        vm.stopPrank();

        uint256 fundsAfter = token1.balanceOf(user2);

        (
            uint256 amount,
            uint256 collateralAmount, // @audit: should always be higher than borrow amount
            uint256 timestamp,
            uint256 rate,
            address collateralToken
        ) = pool.borrowPositions(address(token1), user2);

        assertEq(amount, BORROW_AMOUNT - pool.calculateOwnerFee(BORROW_AMOUNT));
        assertEq(collateralAmount, COLLATERAL_AMOUNT);
        assertEq(timestamp, block.timestamp);
        assertGt(rate, 0); // @audit Update rate
        assertEq(collateralToken, address(token2));
    }

    function testFailBorrowUnsupportedToken() public {
        // Deploy a new token that isn't supported
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS");

        // Try to borrow using unsupported token as collateral
        vm.startPrank(user2);
        pool.borrow(address(token1), BORROW_AMOUNT, address(unsupportedToken), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testFailBorrowUnsupportedBorrowToken() public {
        // Deploy a new token that isn't supported
        MockERC20 unsupportedToken = new MockERC20("Unsupported", "UNS");

        vm.startPrank(user2);
        pool.borrow(
            address(unsupportedToken), // Try to borrow unsupported token
            BORROW_AMOUNT,
            address(token2),
            COLLATERAL_AMOUNT
        );
        vm.stopPrank();
    }

    function testFailBorrowMoreThanAvailable() public {
        // First deposit some tokens to the pool
        vm.prank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT); // Deposit 100 tokens

        // Try to borrow more than what's available
        uint256 tooMuchBorrow = DEPOSIT_AMOUNT * 2; // Try to borrow 200 tokens

        vm.startPrank(user2);
        pool.borrow(address(token1), tooMuchBorrow, address(token2), COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testFailBorrowZeroAmount() public {
        vm.startPrank(user2);
        pool.borrow(
            address(token1),
            0, // Try to borrow 0 tokens
            address(token2),
            COLLATERAL_AMOUNT
        );
        vm.stopPrank();
    }

    // Test successful borrow with minimum collateral
    function testBorrowWithMinimumCollateral() public {
        // First deposit some tokens to the pool
        vm.prank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);

        // Calculate minimum collateral needed (150% of borrow amount)
        uint256 minCollateral = (BORROW_AMOUNT * 150) / 100;

        vm.startPrank(user2);
        pool.borrow(address(token1), BORROW_AMOUNT, address(token2), minCollateral);

        // Verify the borrow position
        (uint256 amount, uint256 collateralAmount, uint256 timestamp, uint256 rate, address collateralToken) =
            pool.borrowPositions(address(token1), user2);

        assertEq(amount, BORROW_AMOUNT - pool.calculateOwnerFee(BORROW_AMOUNT));
        assertEq(collateralAmount, minCollateral);
        assertEq(timestamp, block.timestamp);
        assertGt(rate, 0);
        assertEq(collateralToken, address(token2));
        vm.stopPrank();
    }

    // Test borrow with maximum amount available
    function testBorrowMaximumAvailable() public {
        // First deposit some tokens to the pool
        vm.prank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);

        // Borrow the maximum amount (assuming no other borrows)
        uint256 maxBorrow = DEPOSIT_AMOUNT;
        uint256 requiredCollateral = (maxBorrow * 150) / 100;

        vm.startPrank(user2);
        pool.borrow(address(token1), maxBorrow, address(token2), requiredCollateral);

        // Verify the borrow position
        (uint256 amount,,,,) = pool.borrowPositions(address(token1), user2);
        assertEq(amount, maxBorrow - pool.calculateOwnerFee(maxBorrow));
        vm.stopPrank();
    }

    // Test repayment
    function testRepay() public {
        // Setup: deposit and borrow first
        vm.prank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);

        vm.prank(user2);
        pool.borrow(address(token1), BORROW_AMOUNT, address(token2), COLLATERAL_AMOUNT);

        // Test repayment
        vm.prank(user2);
        pool.repay(address(token1), BORROW_AMOUNT / 2);

        (uint256 amount,,,,) = pool.borrowPositions(address(token1), user2);
        assertEq(amount, (BORROW_AMOUNT - pool.calculateOwnerFee(BORROW_AMOUNT)) / 2);
    }

    // Test withdrawals
    // @audit: This needs to also test for lock periouds.
    // Lender should not be able to withdraw whenever they like and should only do it after initial term is met.
    // What happens after term, and borrower has not returned funds?
    function testWithdraw() public {
        // Setup: deposit first
        vm.prank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);

        uint256 withdrawAmount = DEPOSIT_AMOUNT / 2;
        vm.prank(user1);
        pool.withdraw(address(token1), withdrawAmount);

        (uint256 amount,,) = pool.lendingPositions(address(token1), user1);
        assertEq(amount, DEPOSIT_AMOUNT - pool.calculateOwnerFee(DEPOSIT_AMOUNT) - withdrawAmount);
    }

    // Test interest calculation
    function testCalculateInterest() public {
        vm.prank(user1);
        pool.deposit(address(token1), DEPOSIT_AMOUNT);

        // Advance time by 1 year
        vm.warp(block.timestamp + 365 days);

        uint256 interest = pool.calculateInterest(address(token1), user1);
        assertTrue(interest > 0);
    }
}
