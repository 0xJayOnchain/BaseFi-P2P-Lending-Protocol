// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockAggregator.sol";
import "../src/PriceOracle.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract LiquidationTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    MockAggregator aggLend;
    MockAggregator aggColl;
    PriceOracle oracle;
    LendingPool pool;
    LoanPositionNFT nft;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);

        // deploy price oracle and mocks
        aggLend = new MockAggregator(18, int256(1e18));
        aggColl = new MockAggregator(18, int256(1e18));
        oracle = new PriceOracle();
        oracle.setPriceFeed(address(lendToken), address(aggLend));
        oracle.setPriceFeed(address(collateralToken), address(aggColl));

        pool = new LendingPool(address(oracle));

        // NFT and permissions
        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));

        // fund lender and borrower
        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);
    }

    function testLiquidateAfterExpiry() public {
        // lender creates offer
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId = pool.createLendingOffer(address(lendToken), 100 ether, 600, 90 days, address(collateralToken), 15000);
        vm.stopPrank();

        // borrower accepts
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 150 ether);
        vm.stopPrank();

        // warp past expiry
        vm.warp(block.timestamp + 91 days);

        // liquidate as lender
        vm.startPrank(lender);
        pool.liquidate(loanId);
        vm.stopPrank();

        // loan should be marked liquidated
        (,,,,, uint256 principal, uint256 collateralAmount, , , bool repaid, bool liquidated) = pool.getLoan(loanId);
        assertEq(liquidated, true);
        assertEq(repaid, false);
        assertEq(principal, 100 ether);
        // penalty in lend units = 100 * 200 / 10000 = 2 LEND
        // prices equal -> penaltyCollateral = 2 COLL
        uint256 expectedPenalty = 2 ether;
        uint256 expectedToLiquidator = 150 ether - expectedPenalty;

        assertEq(collateralToken.balanceOf(lender), expectedToLiquidator);
        assertEq(pool.ownerFees(address(collateralToken)), expectedPenalty);

        // NFTs should be burned
        (, , , , , , , uint256 ltid, uint256 btid, , ) = pool.getLoan(loanId);
        vm.expectRevert();
        nft.ownerOf(ltid);
        vm.expectRevert();
        nft.ownerOf(btid);
    }

    function testLiquidateUndercollateralizedByPriceDrop() public {
        // lender creates offer
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId = pool.createLendingOffer(address(lendToken), 100 ether, 600, 90 days, address(collateralToken), 15000);
        vm.stopPrank();

        // borrower accepts
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 150 ether);
        vm.stopPrank();

        // price drop of collateral to 0.5
        aggColl.setAnswer(int256(5e17));

        // liquidate as lender
        vm.startPrank(lender);
        pool.liquidate(loanId);
        vm.stopPrank();

        // loan should be marked liquidated
        (,,,,, uint256 principal, uint256 collateralAmount, , , bool repaid, bool liquidated) = pool.getLoan(loanId);
        assertEq(liquidated, true);
        assertEq(repaid, false);

        // with collateral price halved, penalty as before is 2 LEND -> in collateral units = 2 * 1 / 0.5 = 4 COLL
        // but penalty capped to collateral amount if larger
        uint256 expectedPenaltyCollateral = (2 ether * 1e18) / (5e17); // equals 4e18
        if (expectedPenaltyCollateral > 150 ether) expectedPenaltyCollateral = 150 ether;
        uint256 expectedToLiquidator = 150 ether - expectedPenaltyCollateral;

        assertEq(collateralToken.balanceOf(lender), expectedToLiquidator);
        assertEq(pool.ownerFees(address(collateralToken)), expectedPenaltyCollateral);
    }
}
