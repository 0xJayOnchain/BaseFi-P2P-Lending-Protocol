// SPDX-License-Identifier: MIT
// solhint-disable one-contract-per-file
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "src/LendingPool.sol";
import "src/PriceOracle.sol";
import "src/mocks/MockUniswapV2Router.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @author BaseFi P2P Lending Protocol Tests
/// @notice Minimal ERC20 used within test scenarios
contract MockERC20 is ERC20 {
    /// @notice Simple ERC20 mock used in tests
    /// @param n Token name
    /// @param s Token symbol
    constructor(string memory n, string memory s) ERC20(n, s) {}

    /// @notice Mint new tokens to an address (test-only)
    /// @param to Recipient address
    /// @param amt Amount to mint
    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/// @title RepayWithSwap tests
/// @notice Covers happy path and key guards
/// @title RepayWithSwapTest
/// @author BaseFi P2P Lending Protocol Tests
/// @notice Test suite for repay via swap behavior and guards
contract RepayWithSwapTest is Test {
    /// @notice Lending pool under test
    LendingPool public pool;
    /// @notice Price oracle used by the pool
    PriceOracle public oracle;
    /// @notice Mock UniswapV2 router for swap tests
    MockUniswapV2Router public router;
    /// @notice Mock lend token
    MockERC20 public lendToken;
    /// @notice Mock collateral token
    MockERC20 public collateralToken;
    /// @notice Other token for swap input
    MockERC20 public otherToken;
    /// @notice Test lender address
    address public lender = address(0xABCD);
    /// @notice Test borrower address
    address public borrower = address(0xBEEF);

    /// @notice Set up common contracts and balances for tests
    function setUp() public {
        oracle = new PriceOracle();
        pool = new LendingPool(address(oracle));
        router = new MockUniswapV2Router();
        lendToken = new MockERC20("Lend", "LND");
        collateralToken = new MockERC20("Coll", "COL");
        otherToken = new MockERC20("Other", "OTH");

        // fund actors
        lendToken.mint(lender, 1_000 ether);
        collateralToken.mint(borrower, 1_000 ether);
        otherToken.mint(borrower, 2_000 ether);

        // pre-fund router with lend token to simulate swap outputs
        lendToken.mint(address(router), 10_000 ether);

        // approvals
        vm.prank(lender);
        lendToken.approve(address(pool), type(uint256).max);
        vm.prank(borrower);
        collateralToken.approve(address(pool), type(uint256).max);
        vm.prank(borrower);
        otherToken.approve(address(pool), type(uint256).max);

        // whitelist router
        pool.setRouterWhitelisted(address(router), true);
    }

    /// @notice Helper to create a basic loan offer and accept by borrower
    /// @return loanId The created loan ID
    function _createLoan() internal returns (uint256 loanId) {
        // lender creates offer
        vm.prank(lender);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 500, 30 days, address(collateralToken), 1500);
        // borrower accepts with collateral
        vm.prank(borrower);
        loanId = pool.acceptOfferByBorrower(offerId, 200 ether);
    }

    /// @notice Borrower repays using a swap and loan is closed
    function testRepayWithSwapHappyPath() public {
        uint256 loanId = _createLoan();
        // ensure borrower has otherToken to swap
        address[] memory path = new address[](2);
        path[0] = address(otherToken);
        path[1] = address(lendToken);

        // compute minOut enough to cover due (principal + small interest)
        uint256 interest = pool.accruedInterest(loanId);
        uint256 totalDue = 100 ether + interest;

        vm.prank(borrower);
        pool.repayFullWithSwap(loanId, address(router), 150 ether, path, totalDue, block.timestamp + 1 days);

        // loan marked repaid
        (,,,,,,,,, bool repaid, bool liquidated) = pool.getLoan(loanId);
        assertTrue(repaid, "repaid");
        assertFalse(liquidated, "not liquidated");

        // lender received principal+interest-ownerFee
        // owner fee defaults to 0; so lender gets principal+interest
        assertEq(lendToken.balanceOf(lender), 1_000 ether - 100 ether + (100 ether + interest), "lender balance");
        // borrower got collateral back
        assertEq(collateralToken.balanceOf(borrower), 1_000 ether - 200 ether + 200 ether, "collateral returned");
    }

    /// @notice Repay with swap should revert if router is not whitelisted
    function testRevertsWhenRouterNotWhitelisted() public {
        uint256 loanId = _createLoan();
        address[] memory path = new address[](2);
        path[0] = address(otherToken);
        path[1] = address(lendToken);
        vm.prank(borrower);
        vm.expectRevert(bytes("router not whitelisted"));
        pool.repayFullWithSwap(loanId, address(0x1234), 150 ether, path, 110 ether, block.timestamp + 1 days);
    }

    /// @notice Repay with swap should revert when amountOut is less than total due
    function testRevertsWhenAmountOutInsufficient() public {
        uint256 loanId = _createLoan();
        address[] memory path = new address[](2);
        path[0] = address(otherToken);
        path[1] = address(lendToken);
        uint256 interest = pool.accruedInterest(loanId);
        uint256 totalDue = 100 ether + interest;
        // set amountOutMin less than total due; router will deliver amountOutMin, causing revert
        vm.prank(borrower);
        vm.expectRevert(bytes("insufficient out"));
        pool.repayFullWithSwap(loanId, address(router), 150 ether, path, totalDue - 1, block.timestamp + 1 days);
    }

    /// @notice Repay with swap should revert when protocol is paused
    function testRevertsWhenPaused() public {
        uint256 loanId = _createLoan();
        address[] memory path = new address[](2);
        path[0] = address(otherToken);
        path[1] = address(lendToken);
        pool.pause();
        vm.prank(borrower);
        vm.expectRevert();
        pool.repayFullWithSwap(loanId, address(router), 150 ether, path, 110 ether, block.timestamp + 1 days);
    }

    /// @notice Only the borrower can call repayFullWithSwap
    function testOnlyBorrowerCanRepayWithSwap() public {
        uint256 loanId = _createLoan();
        address[] memory path = new address[](2);
        path[0] = address(otherToken);
        path[1] = address(lendToken);
        vm.prank(lender);
        vm.expectRevert(bytes("only borrower"));
        pool.repayFullWithSwap(loanId, address(router), 150 ether, path, 110 ether, block.timestamp + 1 days);
    }
}
