// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockUniswapV2Router.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract PausableTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    LendingPool pool;
    LoanPositionNFT nft;
    MockUniswapV2Router router;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);
        pool = new LendingPool(address(0));
        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));
        router = new MockUniswapV2Router();

        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);

        // whitelist router for swap test
        pool.setRouterWhitelisted(address(router), true);

        // pause protocol (owner is this test contract)
        pool.pause();
    }

    function testPausedBlocksCreateOffer() public {
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        vm.expectRevert();
        pool.createLendingOffer(address(lendToken), 100 ether, 1000, 90 days, address(collateralToken), 15000);
        vm.stopPrank();
    }

    function testPausedBlocksCreateRequest() public {
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 100 ether);
        vm.expectRevert();
        pool.createBorrowRequest(address(lendToken), 50 ether, 1000, 90 days, address(collateralToken), 100 ether);
        vm.stopPrank();
    }

    function testPausedBlocksAcceptOffer() public {
        // unpause to create offer, then pause again before accept
        pool.unpause();
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 1000, 90 days, address(collateralToken), 15000);
        vm.stopPrank();
        pool.pause();

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        vm.expectRevert();
        pool.acceptOfferByBorrower(offerId, 150 ether);
        vm.stopPrank();
    }

    function testPausedBlocksRepayClaimLiquidateAndSwap() public {
        // unpause to create a loan
        pool.unpause();
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 1000, 30 days, address(collateralToken), 15000);
        vm.stopPrank();

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 150 ether);
        vm.stopPrank();

        // pause and expect reverts
        pool.pause();

        // repay
        vm.startPrank(borrower);
        lendToken.mint(borrower, 1 ether);
        lendToken.approve(address(pool), 101 ether);
        vm.expectRevert();
        pool.repayFull(loanId);
        vm.stopPrank();

        // claim fees
        vm.expectRevert();
        pool.claimOwnerFees(address(lendToken));

        // liquidate
        vm.startPrank(lender);
        vm.expectRevert();
        pool.liquidate(loanId);
        vm.stopPrank();

        // claim and swap fees
        address[] memory path = new address[](2);
        path[0] = address(lendToken);
        path[1] = address(collateralToken);
        vm.expectRevert();
        pool.claimAndSwapFees(address(router), address(lendToken), path, 0, block.timestamp + 1);
    }

    function testPausedBlocksCancelOfferAndRequest() public {
        // unpause to create offer & request
        pool.unpause();
        vm.startPrank(lender);
        lendToken.approve(address(pool), 50 ether);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 50 ether, 600, 15 days, address(collateralToken), 15000);
        vm.stopPrank();

        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 80 ether);
        uint256 reqId =
            pool.createBorrowRequest(address(lendToken), 20 ether, 800, 15 days, address(collateralToken), 80 ether);
        vm.stopPrank();

        // pause and expect cancel reverts
        pool.pause();

        vm.startPrank(lender);
        vm.expectRevert();
        pool.cancelLendingOffer(offerId);
        vm.stopPrank();

        vm.startPrank(borrower);
        vm.expectRevert();
        pool.cancelBorrowRequest(reqId);
        vm.stopPrank();
    }
}
