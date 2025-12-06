// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "src/LendingPool.sol";
import "src/PriceOracle.sol";
import "src/mocks/MockUniswapV2Router.sol";
import "src/mocks/MockAggregator.sol";
import "src/mocks/MockERC20.sol";

/// @title LiquidateWithSwap tests
/// @author BaseFi P2P Lending Protocol Tests
/// @notice Covers opt-in liquidation with swap and key guards
contract LiquidateWithSwapTest is Test {
    /// @notice Lending pool under test
    LendingPool public pool;
    /// @notice Price oracle used by the pool
    PriceOracle public oracle;
    /// @notice Mock UniswapV2 router to simulate swaps
    MockUniswapV2Router public router;
    /// @notice Mock token representing the loan principal currency
    MockERC20 public lendToken;
    /// @notice Mock token used as collateral in the loan
    MockERC20 public collateralToken;
    /// @notice Output token received by the liquidator after swap
    MockERC20 public outToken;
    /// @notice Test lender address
    address public lender = address(0xABCD);
    /// @notice Test borrower address
    address public borrower = address(0xBEEF);

    /// @notice Deploy dependencies, fund actors, set approvals and whitelist router
    function setUp() public {
        oracle = new PriceOracle();
        pool = new LendingPool(address(oracle));
        router = new MockUniswapV2Router();
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);
        outToken = new MockERC20("Out", "OUT", 18);

        // fund actors
        lendToken.mint(lender, 1_000 ether);
        collateralToken.mint(borrower, 1_000 ether);

        // pre-fund router with out token to simulate swap outputs
        outToken.mint(address(router), 10_000 ether);

        // approvals
        vm.prank(lender);
        lendToken.approve(address(pool), type(uint256).max);
        vm.prank(borrower);
        collateralToken.approve(address(pool), type(uint256).max);

        // whitelist router
        pool.setRouterWhitelisted(address(router), true);

        // set oracle feeds for lend and collateral tokens
        MockAggregator lendAgg = new MockAggregator(18, 1e18);
        MockAggregator collAgg = new MockAggregator(18, 1e18);
        oracle.setPriceFeed(address(lendToken), address(lendAgg));
        oracle.setPriceFeed(address(collateralToken), address(collAgg));
    }

    /// @notice Helper: create a loan and advance time past expiration
    /// @return loanId The created and expired loan ID
    function _createExpiredLoan() internal returns (uint256 loanId) {
        // lender offer
        vm.prank(lender);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 0, 1 days, address(collateralToken), 10000);
        // borrower accepts with collateral
        vm.prank(borrower);
        loanId = pool.acceptOfferByBorrower(offerId, 100 ether);
        // fast-forward past expiration
        vm.warp(block.timestamp + 2 days);
    }

    /// @notice Liquidation with swap closes loan and pays liquidator in output token
    function testLiquidateWithSwapHappyPath() public {
        uint256 loanId = _createExpiredLoan();
        address[] memory path = new address[](2);
        path[0] = address(collateralToken);
        path[1] = address(outToken);

        // lender calls liquidation with swap to receive proceeds in OUT token
        vm.prank(lender);
        pool.liquidateWithSwap(loanId, address(router), path, 90 ether, block.timestamp + 1 days);

        // loan marked liquidated
        (,,,,,,,,, bool repaid, bool liquidated) = pool.getLoan(loanId);
        assertFalse(repaid);
        assertTrue(liquidated);

        // liquidator received out tokens (from router), collateral reduced in pool
        assertGt(outToken.balanceOf(lender), 0);
    }

    /// @notice Reverts when router is not whitelisted
    function testLiquidateWithSwapRouterNotWhitelisted() public {
        uint256 loanId = _createExpiredLoan();
        address[] memory path = new address[](2);
        path[0] = address(collateralToken);
        path[1] = address(outToken);
        vm.prank(lender);
        vm.expectRevert(bytes("router not whitelisted"));
        pool.liquidateWithSwap(loanId, address(0x1234), path, 90 ether, block.timestamp + 1 days);
    }

    /// @notice Reverts when path[0] is not the collateral token
    function testLiquidateWithSwapBadPathFirstToken() public {
        uint256 loanId = _createExpiredLoan();
        address[] memory path = new address[](2);
        path[0] = address(outToken);
        path[1] = address(collateralToken);
        vm.prank(lender);
        vm.expectRevert(bytes("path first != collateral"));
        pool.liquidateWithSwap(loanId, address(router), path, 90 ether, block.timestamp + 1 days);
    }

    /// @notice Reverts when protocol is paused
    function testLiquidateWithSwapPaused() public {
        uint256 loanId = _createExpiredLoan();
        address[] memory path = new address[](2);
        path[0] = address(collateralToken);
        path[1] = address(outToken);
        pool.pause();
        vm.prank(lender);
        vm.expectRevert();
        pool.liquidateWithSwap(loanId, address(router), path, 90 ether, block.timestamp + 1 days);
    }

    /// @notice Reverts when caller is not lender nor owner of lender position NFT
    function testLiquidateWithSwapOnlyLenderOrNFT() public {
        uint256 loanId = _createExpiredLoan();
        address[] memory path = new address[](2);
        path[0] = address(collateralToken);
        path[1] = address(outToken);
        vm.prank(borrower);
        vm.expectRevert(bytes("not lender"));
        pool.liquidateWithSwap(loanId, address(router), path, 90 ether, block.timestamp + 1 days);
    }
}
