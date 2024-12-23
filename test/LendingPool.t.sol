// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import "../src/MockERC20.sol";
import "../src/LendingPool.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract LendingPoolTest is Test {
    LendingPool public lendingPool;
    MockERC20 token;
    address mockTokenAddress;
    address userLender = address(1);
    address userBorrower = address(2);

    function setUp() public {
        // Deploy the Lending Pool contract
        lendingPool = new LendingPool();

        // Deploy the Mock ERC-20 token
        token = new MockERC20("Mock Token", "MKT");
        mockTokenAddress = address(token);

        // Mint tokens to the user
        uint256 initialBalance = 1_000 ether; // 1,000 tokens (18 decimals)
        token.mint(userLender, initialBalance);
    }

    function testAddSupportedToken() public {
        // Add a supported token
        lendingPool.addSupportedToken(mockTokenAddress);

        // Read the mapping to check if the token is supported
        bool isSupported = lendingPool.supportedTokens(mockTokenAddress);

        // Assert that the token is supported
        assertTrue(isSupported, "The token should be supported.");
    }

    function testUserBalance() public { 
        // Check the user's balance
        uint256 userBalance = token.balanceOf(userLender);
        assertEq(userBalance, 1_000 ether);
    }

    function testCalculateOwnerFee() public {
        // uint256 balanceBefore = address(this).balance ; // Assuming the lendingPool has a balanceOf function to check the balance
        // console.log("Balance Before: ",  address(this).balance);

        // Add a supported token
        lendingPool.addSupportedToken(mockTokenAddress);
        // Call the function that generates a fee
        uint256 depositAmount = 10000;
        uint256 fee = lendingPool.calculateOwnerFee(depositAmount);
        console.log("Calculated Owner Fee: ", fee);

        // make address(1) incredibly rich
        // vm.deal(address(1), 1000000000000000000000000000000);
        // console.log("Balance of address(1): ",  address(1).balance);
        
        // Use a separate address to make a deposit
        vm.startPrank(address(1));
        IERC20(mockTokenAddress).approve(address(lendingPool), depositAmount); // Approve LendingPool contract to spend tokens
        // Perform the action that should generate a fee (e.g., making a deposit or performing a lending action)
        lendingPool.deposit(mockTokenAddress, depositAmount); // Replace with the actual function that causes the fee to be transferred
        vm.stopPrank();
        
        // Check the owner's balance after the fee is generated
        uint256 balanceAfter = address(this).balance;
        console.log("Balance After: ", balanceAfter);

        // Log the balances for inspection
        console.log("Owner Balance Before: ", balanceBefore);
        console.log("Owner Balance After: ", balanceAfter);

        // Assert that the owner's balance has increased by at least the fee amount
        assertTrue(balanceAfter > balanceBefore, "Owner's balance did not increase after fee.");
        assertTrue(balanceAfter - balanceBefore >= fee, "Owner's balance did not increase by the correct fee amount.");
    }
}
