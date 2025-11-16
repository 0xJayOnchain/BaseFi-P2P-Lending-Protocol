// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract ClaimFeesTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    LendingPool pool;
    LoanPositionNFT nft;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);

    pool = new LendingPool(address(this));

        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));

        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);
    }

    function testOwnerFeeAccruesAndCanBeClaimed() public {
        // set owner fee to 500 bps (5%)
        pool.setOwnerFeeBPS(500);

        // lender creates offer
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId = pool.createLendingOffer(address(lendToken), 100 ether, 1000, 90 days, address(collateralToken), 15000);
        vm.stopPrank();

        // borrower accepts
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 150 ether);

        // advance time 30 days to accrue interest
        vm.warp(block.timestamp + 30 days);

        uint256 interest = pool.accruedInterest(loanId);
        uint256 total = 100 ether + interest;
        // ensure borrower has tokens to repay
        lendToken.mint(borrower, interest);
        lendToken.approve(address(pool), total);

        pool.repayFull(loanId);

    // ownerFees for lendToken should be > 0
    uint256 f = pool.ownerFees(address(lendToken));
    assertGt(f, 0);

    // stop being borrower and claim fees as owner (this contract)
    vm.stopPrank();

    uint256 balBefore = lendToken.balanceOf(address(this));
    pool.claimOwnerFees(address(lendToken));
    uint256 balAfter = lendToken.balanceOf(address(this));
    assertEq(balAfter - balBefore, f);

    // ownerFees should be zeroed
    assertEq(pool.ownerFees(address(lendToken)), 0);
    }

    function testClaimFeesMultipleTokens() public {
        // set owner fee to 500 bps (5%)
        pool.setOwnerFeeBPS(500);

        // Create a second lend token
        MockERC20 lendToken2 = new MockERC20("Lend2", "LND2", 18);
        lendToken2.mint(lender, 1000 ether);

        // --- Loan 1 with lendToken (existing lendToken from setUp)
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offer1 = pool.createLendingOffer(address(lendToken), 100 ether, 1000, 90 days, address(collateralToken), 15000);
        vm.stopPrank();

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        uint256 loan1 = pool.acceptOfferByBorrower(offer1, 150 ether);
        vm.warp(block.timestamp + 30 days);
        uint256 interest1 = pool.accruedInterest(loan1);
        lendToken.mint(borrower, interest1);
        lendToken.approve(address(pool), 100 ether + interest1);
        pool.repayFull(loan1);
        vm.stopPrank();

        uint256 f1 = pool.ownerFees(address(lendToken));
        assertGt(f1, 0);

        // --- Loan 2 with lendToken2
        vm.startPrank(lender);
        lendToken2.approve(address(pool), 200 ether);
        uint256 offer2 = pool.createLendingOffer(address(lendToken2), 200 ether, 2000, 90 days, address(collateralToken), 15000);
        vm.stopPrank();

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 300 ether);
        uint256 loan2 = pool.acceptOfferByBorrower(offer2, 300 ether);
        vm.warp(block.timestamp + 15 days);
        uint256 interest2 = pool.accruedInterest(loan2);
        lendToken2.mint(borrower, interest2);
        lendToken2.approve(address(pool), 200 ether + interest2);
        pool.repayFull(loan2);
        vm.stopPrank();

        uint256 f2 = pool.ownerFees(address(lendToken2));
        assertGt(f2, 0);

        // Claim both as owner (this contract is owner)
        uint256 bal1Before = lendToken.balanceOf(address(this));
        uint256 bal2Before = lendToken2.balanceOf(address(this));
        pool.claimOwnerFees(address(lendToken));
        pool.claimOwnerFees(address(lendToken2));
        uint256 bal1After = lendToken.balanceOf(address(this));
        uint256 bal2After = lendToken2.balanceOf(address(this));

        assertEq(bal1After - bal1Before, f1);
        assertEq(bal2After - bal2Before, f2);
        assertEq(pool.ownerFees(address(lendToken)), 0);
        assertEq(pool.ownerFees(address(lendToken2)), 0);
    }
}
