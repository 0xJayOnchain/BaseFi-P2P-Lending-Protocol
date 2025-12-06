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
}
