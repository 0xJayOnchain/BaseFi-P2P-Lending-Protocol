// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/LendingPool.sol";
import "../src/PriceOracle.sol";
import "../src/mocks/MockAggregator.sol";

contract LendingPoolOfferRequestTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    LendingPool pool;
    PriceOracle oracle;
    MockAggregator agg;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Collateral", "COL", 18);

        // deploy oracle + mock
        oracle = new PriceOracle();
        agg = new MockAggregator(18, int256(1e18));
        oracle.setPriceFeed(address(collateralToken), address(agg));

        pool = new LendingPool(address(oracle));

        // mint and distribute
        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);
    }

    function testCreateAndCancelLendingOffer() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 id = pool.createLendingOffer(address(lendToken), 100 ether, 600, 90 days, address(collateralToken), 15000);
        // pool should hold tokens
        assertEq(lendToken.balanceOf(address(pool)), 100 ether);

        // cancel
        pool.cancelLendingOffer(id);
        assertEq(lendToken.balanceOf(lender), 1000 ether);
        vm.stopPrank();
    }

    function testCreateAndCancelBorrowRequest() public {
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 500 ether);
        uint256 id = pool.createBorrowRequest(address(lendToken), 50 ether, 800, 90 days, address(collateralToken), 500 ether);
        assertEq(collateralToken.balanceOf(address(pool)), 500 ether);

        pool.cancelBorrowRequest(id);
        assertEq(collateralToken.balanceOf(borrower), 2000 ether);
        vm.stopPrank();
    }

    function testCancelOfferOnlyByLender() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 10 ether);
        uint256 id = pool.createLendingOffer(address(lendToken), 10 ether, 600, 30 days, address(collateralToken), 15000);
        vm.stopPrank();

        vm.prank(borrower);
        vm.expectRevert(bytes("only lender"));
        pool.cancelLendingOffer(id);
    }

    function testCancelRequestOnlyByBorrower() public {
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 20 ether);
        uint256 id = pool.createBorrowRequest(address(lendToken), 5 ether, 800, 30 days, address(collateralToken), 20 ether);
        vm.stopPrank();

        vm.prank(lender);
        vm.expectRevert(bytes("only borrower"));
        pool.cancelBorrowRequest(id);
    }
}
