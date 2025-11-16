// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract ClaimFeesTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    LendingPool pool;
    LoanPositionNFT nft;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);

    pool = new LendingPool(address(this));

        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));

        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);
    }

    function testOwnerFeeAccruesAndCanBeClaimed() public {
        // set owner fee to 500 bps (5%)
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

        // advance time 30 days to accrue interest
        vm.warp(block.timestamp + 30 days);

        uint256 interest = pool.accruedInterest(loanId);
        uint256 total = 100 ether + interest;
        // ensure borrower has tokens to repay
        lendToken.mint(borrower, interest);
        lendToken.approve(address(pool), total);

        pool.repayFull(loanId);

    // ownerFees for lendToken should be > 0
    uint256 f = pool.ownerFees(address(lendToken));
    assertGt(f, 0);

    // stop being borrower and claim fees as owner (this contract)
    vm.stopPrank();

    uint256 balBefore = lendToken.balanceOf(address(this));
    pool.claimOwnerFees(address(lendToken));
    uint256 balAfter = lendToken.balanceOf(address(this));
    assertEq(balAfter - balBefore, f);

    // ownerFees should be zeroed
    assertEq(pool.ownerFees(address(lendToken)), 0);
    }
}
