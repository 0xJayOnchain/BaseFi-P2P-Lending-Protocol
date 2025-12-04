// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";
import "../src/mocks/MockFeeOnTransferERC20.sol";
import "../src/mocks/MockNoReturnERC20.sol";
import "../src/mocks/MockERC20.sol";

contract ERC20EdgeCasesTest is Test {
    LendingPool pool;
    LoanPositionNFT nft;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        pool = new LendingPool(address(0));
        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));
    }

    function testFeeOnTransferTokenCausesInsufficientEscrow() public {
        // Lend token takes 1% fee on transfer
        MockFeeOnTransferERC20 lendToken = new MockFeeOnTransferERC20("FeeLend", "FLND", 18, 100);
        MockERC20 collToken = new MockERC20("Coll", "COL", 18);
        lendToken.mint(lender, 100 ether);
        collToken.mint(borrower, 200 ether);

        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        // create offer of 100 ether; due to 1% fee, pool will receive only 99 ether
        uint256 offerId = pool.createLendingOffer(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 10000);
        vm.stopPrank();

        // borrower tries to accept, expecting principal transfer of 100 ether from pool, but pool only holds 99 ether
        vm.startPrank(borrower);
        collToken.approve(address(pool), 100 ether);
        vm.expectRevert(); // SafeERC20 transfer should revert due to insufficient balance
        pool.acceptOfferByBorrower(offerId, 100 ether);
        vm.stopPrank();
    }

    function testNoReturnERC20WorksWithSafeERC20() public {
        // Use MockNoReturnERC20 as collateral; SafeERC20 should still work
        MockERC20 lendToken = new MockERC20("Lend", "LND", 18);
        MockNoReturnERC20 collToken = new MockNoReturnERC20();
        lendToken.mint(lender, 100 ether);
        collToken.mint(borrower, 100 ether);

        vm.startPrank(lender);
        lendToken.approve(address(pool), 50 ether);
        uint256 offerId = pool.createLendingOffer(address(lendToken), 50 ether, 500, 7 days, address(collToken), 10000);
        vm.stopPrank();

        vm.startPrank(borrower);
        collToken.approve(address(pool), 50 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 50 ether);
        assertEq(loanId, 1);
        vm.stopPrank();
    }

    function testUnusualDecimalsTokens() public {
        // Lend token 6 decimals, collateral 18 decimals
        MockERC20 lendToken6 = new MockERC20("Lend6", "L6", 6);
        MockERC20 collToken18 = new MockERC20("Coll18", "C18", 18);
        lendToken6.mint(lender, 1_000_000_000); // 1,000,000.000 units = 1,000,000 tokens with 6 decimals
        collToken18.mint(borrower, 1000 ether);

        vm.startPrank(lender);
        lendToken6.approve(address(pool), 1_000_000); // 1.0 token with 6 decimals
        uint256 offerId = pool.createLendingOffer(address(lendToken6), 1_000_000, 500, 7 days, address(collToken18), 10000);
        vm.stopPrank();

        vm.startPrank(borrower);
        collToken18.approve(address(pool), 1 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 1 ether);
        assertEq(loanId, 1);
        vm.stopPrank();
    }
}
