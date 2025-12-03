// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/PriceOracle.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";
import "../src/mocks/MockAggregator.sol";

contract CollateralValidationTest is Test {
    MockERC20 lendToken;
    MockERC20 collToken;
    LendingPool pool;
    PriceOracle oracle;
    LoanPositionNFT nft;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

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
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));

        lendToken.mint(lender, 1000 ether);
        collToken.mint(borrower, 2000 ether);
    }

    function testExactCollateralPasses() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId = pool.createLendingOffer(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 10000); // 100% ratio
        vm.stopPrank();

        vm.startPrank(borrower);
        collToken.approve(address(pool), 100 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 100 ether);
        assertEq(loanId, 1);
        vm.stopPrank();
    }

    function testUnderCollateralReverts() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId = pool.createLendingOffer(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 10000); // 100% ratio
        vm.stopPrank();

        vm.startPrank(borrower);
        collToken.approve(address(pool), 99 ether);
        vm.expectRevert(bytes("insufficient collateral"));
        pool.acceptOfferByBorrower(offerId, 99 ether);
        vm.stopPrank();
    }

    function testAcceptRequestValidation() public {
        // borrower posts request with collateral amount exactly 100% of principal value
        vm.startPrank(borrower);
        collToken.approve(address(pool), 100 ether);
        uint256 reqId = pool.createBorrowRequest(address(lendToken), 100 ether, 1000, 30 days, address(collToken), 100 ether);
        vm.stopPrank();

        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 loanId = pool.acceptRequestByLender(reqId);
        assertEq(loanId, 1);
        vm.stopPrank();
    }
}
