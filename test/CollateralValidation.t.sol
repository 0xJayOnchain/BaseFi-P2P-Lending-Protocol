// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/PriceOracle.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";
import "../src/mocks/MockAggregator.sol";

/// @title CollateralValidationTest
/// @author BaseFi
/// @notice Tests collateral validation behavior with PriceOracle integration.
contract CollateralValidationTest is Test {
    // re-declare event for matching
    /// @notice Emitted when collateral validation enforcement is toggled
    /// @param enabled Whether enforcement is enabled
    event EnforceCollateralValidationSet(bool enabled);

    /// @notice Lend token used in tests
    MockERC20 internal lendToken;
    /// @notice Collateral token used in tests
    MockERC20 internal collToken;
    /// @notice Pool under test
    LendingPool internal pool;
    /// @notice Oracle used to provide normalized prices
    PriceOracle internal oracle;
    /// @notice Position NFT used for mint/burn
    LoanPositionNFT internal nft;

    /// @notice Test lender address
    address internal lender = address(0xBEEF);
    /// @notice Test borrower address
    address internal borrower = address(0xCAFE);

    /// @notice Configure tokens, oracle, pool, and balances before each test
    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collToken = new MockERC20("Coll", "COL", 18);

        // Set up oracle: both tokens priced at 1e18
        MockAggregator aggL = new MockAggregator(18, int256(1e18));
        MockAggregator aggC = new MockAggregator(18, int256(1e18));
        oracle = new PriceOracle();
        oracle.setPriceFeed(address(lendToken), address(aggL));
        oracle.setPriceFeed(address(collToken), address(aggC));

        pool = new LendingPool(address(oracle));
        pool.setEnforceCollateralValidation(true);

        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 minterRole = keccak256("MINTER_ROLE");
        nft.grantRole(minterRole, address(pool));
        pool.setLoanPositionNFT(address(nft));

        lendToken.mint(lender, 1000 ether);
        collToken.mint(borrower, 2000 ether);
    }

    /// @notice Toggling collateral validation flag changes pool state
    function testToggleCollateralValidation() public {
        // toggle off
        pool.setEnforceCollateralValidation(false);
        assertEq(pool.enforceCollateralValidation(), false);
        // toggle on again
        pool.setEnforceCollateralValidation(true);
        assertEq(pool.enforceCollateralValidation(), true);
    }

    /// @notice Exact collateral equal to principal value passes validation
    function testExactCollateralPasses() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 10000); // 100% ratio
        vm.stopPrank();

        vm.startPrank(borrower);
        collToken.approve(address(pool), 100 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 100 ether);
        assertEq(loanId, 1);
        vm.stopPrank();
    }

    /// @notice Under-collateralized attempt reverts with validation enabled
    function testUnderCollateralReverts() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 10000); // 100% ratio
        vm.stopPrank();

        vm.startPrank(borrower);
        collToken.approve(address(pool), 99 ether);
        vm.expectRevert(bytes("insufficient collateral"));
        pool.acceptOfferByBorrower(offerId, 99 ether);
        vm.stopPrank();
    }

    /// @notice Lender acceptance validates posted collateral when enabled
    function testAcceptRequestValidation() public {
        // borrower posts request with collateral amount exactly 100% of principal value
        vm.startPrank(borrower);
        collToken.approve(address(pool), 100 ether);
        uint256 reqId =
            pool.createBorrowRequest(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 100 ether);
        vm.stopPrank();

        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 loanId = pool.acceptRequestByLender(reqId);
        assertEq(loanId, 1);
        vm.stopPrank();
    }
}
