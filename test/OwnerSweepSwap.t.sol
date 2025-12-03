// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV2Router.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract OwnerSweepSwapTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    MockERC20 usdc;
    LendingPool pool;
    LoanPositionNFT nft;
    MockUniswapV2Router router;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        // owner is this test contract
        pool = new LendingPool(address(0x1));

        // NFT grant (not strictly needed for this test)
        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));

        router = new MockUniswapV2Router();

    // whitelist the router for swaps
    pool.setRouterWhitelisted(address(router), true);

        // fund lender and borrower
        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);
    }

    function testOwnerClaimAndSwapFeesSingleToken() public {
        // set owner fee to 500 bps for noticeable accrued fees
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
        vm.warp(block.timestamp + 30 days);
        uint256 interest = pool.accruedInterest(loanId);
        uint256 total = 100 ether + interest;
        lendToken.mint(borrower, interest);
        lendToken.approve(address(pool), total);
        pool.repayFull(loanId);
        vm.stopPrank();

        // ownerFees in lendToken should be > 0
        uint256 f = pool.ownerFees(address(lendToken));
        assertGt(f, 0);

        // Pre-fund router with USDC to simulate swap out
        // We decide minOut to be half of f for test simplicity (arbitrary ratio)
        uint256 minOut = f / 2;
        usdc.mint(address(router), minOut);

        address[] memory path = new address[](2);
        path[0] = address(lendToken);
        path[1] = address(usdc);

        uint256 ownerUsdcBefore = usdc.balanceOf(address(this));
        pool.claimAndSwapFees(address(router), address(lendToken), path, minOut, block.timestamp + 1);
        uint256 ownerUsdcAfter = usdc.balanceOf(address(this));

        // owner should have received minOut USDC and lendToken ownerFees should be zero
        assertEq(ownerUsdcAfter - ownerUsdcBefore, minOut);
        assertEq(pool.ownerFees(address(lendToken)), 0);
    }
}
