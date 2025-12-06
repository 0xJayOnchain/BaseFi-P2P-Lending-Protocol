// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {LendingPool} from "src/LendingPool.sol";
import {MockERC20} from "src/mocks/MockERC20.sol";

/// @notice Unit tests for risk controls: caps and max duration
contract RiskControlsTest is Test {
    LendingPool pool;
    MockERC20 lendToken;
    MockERC20 collateralToken;

    address owner = address(0xA11CE);
    address lender = address(0xBEEF);
    address borrower = address(0xC0FFEE);

    function setUp() public {
        // deploy pool with no oracle (address(0) is acceptable; validation is opt-in)
        vm.prank(owner);
        pool = new LendingPool(address(0));
        vm.prank(owner);
        // defaults: bands/caps disabled (0), not paused

        // deploy tokens
        lendToken = new MockERC20("LendToken", "LND", 18);
        collateralToken = new MockERC20("CollToken", "COL", 18);

        // mint balances
        lendToken.mint(lender, 1_000_000 ether);
        lendToken.mint(borrower, 1_000_000 ether); // for repay
        collateralToken.mint(borrower, 1_000_000 ether);

        // approvals: lender for lending offer, borrower for collateral and repay
        vm.prank(lender);
        lendToken.approve(address(pool), type(uint256).max);
        vm.prank(borrower);
        collateralToken.approve(address(pool), type(uint256).max);
        vm.prank(borrower);
        lendToken.approve(address(pool), type(uint256).max);
    }

    /// @notice Asset cap enforces limit on active principal by asset
    function test_AssetCap_enforced_and_decrements_on_close() public {
        uint256 principal = 100 ether;
        uint256 interestBps = 0; // simplify repay to principal
        uint256 duration = 30 days;

        // lender creates offer (escrow into pool)
        vm.prank(lender);
        uint256 offerId = pool.createLendingOffer(
            address(lendToken), principal, interestBps, duration, address(collateralToken), 10000
        );

        // set asset cap below principal -> expect revert on accept
        vm.prank(owner);
        pool.setAssetCap(address(lendToken), principal - 1);
        vm.prank(borrower);
        vm.expectRevert(bytes("asset cap"));
        pool.acceptOfferByBorrower(offerId, 200 ether);

        // set asset cap equal to principal -> accept works and increments trackers
        vm.prank(owner);
        pool.setAssetCap(address(lendToken), principal);
        vm.prank(borrower);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 200 ether);

        assertEq(pool.globalActivePrincipal(), principal, "global active principal");
        assertEq(pool.activePrincipalByAsset(address(lendToken)), principal, "asset active principal");
        assertEq(pool.activeBorrowPrincipal(borrower), principal, "borrower active principal");
        assertEq(pool.activeLendPrincipal(lender), principal, "lender active principal");

        // borrower repays full (interest 0)
        vm.prank(borrower);
        pool.repayFull(loanId);

        assertEq(pool.globalActivePrincipal(), 0, "global principal cleared");
        assertEq(pool.activePrincipalByAsset(address(lendToken)), 0, "asset principal cleared");
        assertEq(pool.activeBorrowPrincipal(borrower), 0, "borrower principal cleared");
        assertEq(pool.activeLendPrincipal(lender), 0, "lender principal cleared");
    }

    /// @notice Borrower cap enforces limit on active principal per borrower
    function test_BorrowerCap_enforced_and_decrements_on_close() public {
        uint256 principal = 50 ether;
        uint256 interestBps = 0;
        uint256 duration = 10 days;

        vm.prank(lender);
        uint256 offerId = pool.createLendingOffer(
            address(lendToken), principal, interestBps, duration, address(collateralToken), 10000
        );

        // cap below principal -> revert
        vm.prank(owner);
        pool.setBorrowerCap(borrower, principal - 1);
        vm.prank(borrower);
        vm.expectRevert(bytes("borrower cap"));
        pool.acceptOfferByBorrower(offerId, 100 ether);

        // cap equal -> accept
        vm.prank(owner);
        pool.setBorrowerCap(borrower, principal);
        vm.prank(borrower);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 100 ether);

        assertEq(pool.activeBorrowPrincipal(borrower), principal);

        vm.prank(borrower);
        pool.repayFull(loanId);
        assertEq(pool.activeBorrowPrincipal(borrower), 0);
    }

    /// @notice Lender cap enforces limit on active principal per lender when accepting requests
    function test_LenderCap_enforced_and_decrements_on_close() public {
        uint256 principal = 75 ether;
        uint256 maxRateBps = 0;
        uint256 duration = 5 days;

        // borrower creates request (escrow collateral)
        vm.prank(borrower);
        uint256 requestId = pool.createBorrowRequest(
            address(lendToken), principal, maxRateBps, duration, address(collateralToken), 200 ether
        );

        // set lender cap below principal -> revert
        vm.prank(owner);
        pool.setLenderCap(lender, principal - 1);
        vm.prank(lender);
        vm.expectRevert(bytes("lender cap"));
        pool.acceptRequestByLender(requestId);

        // set cap equal -> accept
        vm.prank(owner);
        pool.setLenderCap(lender, principal);
        vm.prank(lender);
        uint256 loanId = pool.acceptRequestByLender(requestId);

        assertEq(pool.activeLendPrincipal(lender), principal);

        vm.prank(borrower);
        pool.repayFull(loanId);
        assertEq(pool.activeLendPrincipal(lender), 0);
    }

    /// @notice Global cap enforces total active principal across all assets
    function test_GlobalCap_enforced_and_decrements_on_close() public {
        uint256 principal = 120 ether;
        uint256 interestBps = 0;
        uint256 duration = 20 days;

        vm.prank(lender);
        uint256 offerId = pool.createLendingOffer(
            address(lendToken), principal, interestBps, duration, address(collateralToken), 10000
        );

        vm.prank(owner);
        pool.setGlobalActivePrincipalCap(principal - 1);
        vm.prank(borrower);
        vm.expectRevert(bytes("global cap"));
        pool.acceptOfferByBorrower(offerId, 150 ether);

        vm.prank(owner);
        pool.setGlobalActivePrincipalCap(principal);
        vm.prank(borrower);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 150 ether);
        assertEq(pool.globalActivePrincipal(), principal);

        vm.prank(borrower);
        pool.repayFull(loanId);
        assertEq(pool.globalActivePrincipal(), 0);
    }

    /// @notice Max duration enforces an upper bound on loan duration
    function test_MaxDuration_enforced() public {
        uint256 principal = 10 ether;
        uint256 interestBps = 0;

        // duration above cap -> revert
        vm.prank(owner);
        pool.setMaxDurationSecs(5 days);
        vm.prank(lender);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), principal, interestBps, 6 days, address(collateralToken), 10000);

        vm.prank(borrower);
        vm.expectRevert(bytes("duration>max"));
        pool.acceptOfferByBorrower(offerId, 50 ether);

        // create a new compliant offer
        vm.prank(lender);
        uint256 offerOk =
            pool.createLendingOffer(address(lendToken), principal, interestBps, 4 days, address(collateralToken), 10000);
        vm.prank(borrower);
        uint256 loanId = pool.acceptOfferByBorrower(offerOk, 50 ether);
        assertEq(pool.globalActivePrincipal(), principal);

        vm.prank(borrower);
        pool.repayFull(loanId);
        assertEq(pool.globalActivePrincipal(), 0);
    }

    /// @notice Interest rate band enforced on offer interestRateBPS and request maxInterestRateBPS
    function test_InterestRateBand_enforced_on_offer_and_request() public {
        // Configure band: min=100 bps, max=500 bps
        vm.prank(owner);
        pool.setInterestRateBand(100, 500);

        // Offer with rate below min -> revert at create
        vm.prank(lender);
        vm.expectRevert(bytes("rate<min"));
        pool.createLendingOffer(address(lendToken), 10 ether, 50, 3 days, address(collateralToken), 10000);

        // Offer with rate above max -> revert at create
        vm.prank(lender);
        vm.expectRevert(bytes("rate>max"));
        pool.createLendingOffer(address(lendToken), 10 ether, 600, 3 days, address(collateralToken), 10000);

        // Offer within band -> ok
        vm.prank(lender);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 10 ether, 200, 3 days, address(collateralToken), 10000);

        // Request path: borrower sets maxInterestRate; band enforced at acceptRequestByLender
        // Request with max below min -> revert at accept
        vm.prank(borrower);
        uint256 reqLow =
            pool.createBorrowRequest(address(lendToken), 10 ether, 50, 3 days, address(collateralToken), 100 ether);
        vm.prank(lender);
        vm.expectRevert(bytes("rate<min"));
        pool.acceptRequestByLender(reqLow);

        // Request with max above max -> revert at accept
        vm.prank(borrower);
        uint256 reqHigh =
            pool.createBorrowRequest(address(lendToken), 10 ether, 600, 3 days, address(collateralToken), 100 ether);
        vm.prank(lender);
        vm.expectRevert(bytes("rate>max"));
        pool.acceptRequestByLender(reqHigh);

        // Request with max within band -> ok
        vm.prank(borrower);
        uint256 reqOk =
            pool.createBorrowRequest(address(lendToken), 10 ether, 300, 3 days, address(collateralToken), 100 ether);
        vm.prank(lender);
        uint256 loanIdReq = pool.acceptRequestByLender(reqOk);
        assertEq(pool.globalActivePrincipal(), 10 ether);

        // Accept offer too, to ensure both paths remain functional under band
        vm.prank(borrower);
        uint256 loanIdOffer = pool.acceptOfferByBorrower(offerId, 100 ether);
        assertEq(pool.globalActivePrincipal(), 20 ether);

        // Repay both
        vm.prank(borrower);
        pool.repayFull(loanIdReq);
        vm.prank(borrower);
        pool.repayFull(loanIdOffer);
        assertEq(pool.globalActivePrincipal(), 0);
    }

    /// @notice Multiple concurrent loans accumulate toward caps and enforce cumulatively
    function test_CumulativeCaps_multipleLoans_enforced() public {
        // Set caps: asset cap 150, borrower cap 150, lender cap 150, global cap 200
        vm.startPrank(owner);
        pool.setAssetCap(address(lendToken), 150 ether);
        pool.setBorrowerCap(borrower, 150 ether);
        pool.setLenderCap(lender, 150 ether);
        pool.setGlobalActivePrincipalCap(200 ether);
        vm.stopPrank();

        // Create two offers: 100 and 50 principal
        vm.prank(lender);
        uint256 offerA =
            pool.createLendingOffer(address(lendToken), 100 ether, 0, 7 days, address(collateralToken), 10000);
        vm.prank(lender);
        uint256 offerB =
            pool.createLendingOffer(address(lendToken), 50 ether, 0, 7 days, address(collateralToken), 10000);

        // Accept first offer -> totals = 100
        vm.prank(borrower);
        uint256 loanA = pool.acceptOfferByBorrower(offerA, 200 ether);
        assertEq(pool.globalActivePrincipal(), 100 ether);
        assertEq(pool.activePrincipalByAsset(address(lendToken)), 100 ether);
        assertEq(pool.activeBorrowPrincipal(borrower), 100 ether);
        assertEq(pool.activeLendPrincipal(lender), 100 ether);

        // Accept second offer -> totals = 150 (within caps)
        vm.prank(borrower);
        uint256 loanB = pool.acceptOfferByBorrower(offerB, 200 ether);
        assertEq(pool.globalActivePrincipal(), 150 ether);
        assertEq(pool.activePrincipalByAsset(address(lendToken)), 150 ether);
        assertEq(pool.activeBorrowPrincipal(borrower), 150 ether);
        assertEq(pool.activeLendPrincipal(lender), 150 ether);

        // Try a third small offer that would exceed asset/borrower/lender caps (e.g., +10 -> 160 > 150)
        vm.prank(lender);
        uint256 offerC =
            pool.createLendingOffer(address(lendToken), 10 ether, 0, 7 days, address(collateralToken), 10000);
        vm.prank(borrower);
        vm.expectRevert(bytes("asset cap"));
        pool.acceptOfferByBorrower(offerC, 50 ether);

        // Repay one loan -> frees capacity
        vm.prank(borrower);
        pool.repayFull(loanA);
        assertEq(pool.globalActivePrincipal(), 50 ether);

        // Now accept the third offer (still respects borrower/lender/global caps)
        vm.prank(borrower);
        uint256 loanC = pool.acceptOfferByBorrower(offerC, 50 ether);
        assertEq(pool.globalActivePrincipal(), 60 ether);

        // Repay remaining loans
        vm.prank(borrower);
        pool.repayFull(loanB);
        vm.prank(borrower);
        pool.repayFull(loanC);
        assertEq(pool.globalActivePrincipal(), 0);
    }
}
