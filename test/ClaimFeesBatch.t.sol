// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "src/LendingPool.sol";
import "src/mocks/MockERC20.sol";

/// @title ClaimFeesBatch tests
/// @notice Validates batch owner fee claims across multiple tokens
contract ClaimFeesBatchTest is Test {
    LendingPool pool;
    MockERC20 tokenA;
    MockERC20 tokenB;
    MockERC20 tokenC;
    address ownerAddr;
    address lender = address(0xABCD);
    address borrower = address(0xBEEF);

    function setUp() public {
        PriceOracle oracle = new PriceOracle();
        pool = new LendingPool(address(oracle));
        ownerAddr = address(this);

        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);
        tokenC = new MockERC20("TokenC", "TKC", 18);

        // fund actors
        tokenA.mint(lender, 1_000 ether);
        tokenB.mint(lender, 1_000 ether);
        tokenC.mint(lender, 1_000 ether);

        // approvals for pool
        vm.prank(lender);
        tokenA.approve(address(pool), type(uint256).max);
        vm.prank(lender);
        tokenB.approve(address(pool), type(uint256).max);
        vm.prank(lender);
        tokenC.approve(address(pool), type(uint256).max);

        // set owner fee BPS to 100 (1%) to accrue fees
        pool.setOwnerFeeBPS(100);
    }

    function _openAndRepay(LendingPool p, MockERC20 tkn) internal {
        // lender creates offer, borrower accepts, then borrower repays to accrue owner fees
        vm.prank(lender);
        uint256 offerId = p.createLendingOffer(address(tkn), 100 ether, 1000, 7 days, address(tokenC), 10000);
        tokenC.mint(borrower, 500 ether);
        vm.prank(borrower);
        tokenC.approve(address(p), type(uint256).max);
        vm.prank(borrower);
        uint256 loanId = p.acceptOfferByBorrower(offerId, 200 ether);
        // borrower repays full after some time
        vm.warp(block.timestamp + 3 days);
        vm.prank(borrower);
        tkn.mint(borrower, 1_000 ether);
        vm.prank(borrower);
        tkn.approve(address(p), type(uint256).max);
        vm.prank(borrower);
        p.repayFull(loanId);
    }

    function testClaimFeesBatchHappyPath() public {
        _openAndRepay(pool, tokenA);
        _openAndRepay(pool, tokenB);
        // tokenC has no owner fees (collateral token in flows)

        uint256 beforeA = tokenA.balanceOf(ownerAddr);
        uint256 beforeB = tokenB.balanceOf(ownerAddr);
        uint256 beforeC = tokenC.balanceOf(ownerAddr);

        address[] memory tokens = new address[](3);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);
        tokens[2] = address(tokenC);

        pool.claimOwnerFeesBatch(tokens);

        // owner balance increased for tokens with non-zero fees; tokenC unchanged
        assertGt(tokenA.balanceOf(ownerAddr), beforeA);
        assertGt(tokenB.balanceOf(ownerAddr), beforeB);
        assertEq(tokenC.balanceOf(ownerAddr), beforeC);
    }

    function testClaimFeesBatchSkipsZeroFees() public {
        // no fees accrued for tokenC
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenC);
        // should not revert, but also not change balances
        uint256 before = tokenC.balanceOf(ownerAddr);
        pool.claimOwnerFeesBatch(tokens);
        assertEq(tokenC.balanceOf(ownerAddr), before);
    }

    function testClaimFeesBatchRevertsOnEmptyList() public {
        address[] memory tokens = new address[](0);
        vm.expectRevert(bytes("no tokens"));
        pool.claimOwnerFeesBatch(tokens);
    }
}
