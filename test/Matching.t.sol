// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../src/mocks/MockERC20.sol";
import "../src/LendingPool.sol";
import "../src/LoanPositionNFT.sol";

contract MatchingTest is Test {
    MockERC20 lendToken;
    MockERC20 collateralToken;
    LendingPool pool;
    LoanPositionNFT nft;

    address lender = address(0xBEEF);
    address borrower = address(0xCAFE);

    function setUp() public {
        lendToken = new MockERC20("Lend", "LND", 18);
        collateralToken = new MockERC20("Coll", "COL", 18);

        // deploy oracle dummy
        address dummyOracle = address(0x1);
        pool = new LendingPool(dummyOracle);

        // deploy NFT and grant MINTER_ROLE to pool
        nft = new LoanPositionNFT("LoanPos", "LPOS");
        bytes32 MINTER = keccak256("MINTER_ROLE");
        nft.grantRole(MINTER, address(pool));
        pool.setLoanPositionNFT(address(nft));

        // fund lender and borrower
        lendToken.mint(lender, 1000 ether);
        collateralToken.mint(borrower, 2000 ether);
    }

    function testAcceptOfferByBorrowerAndRepayBurnsNFTs() public {
        // lender creates offer (escrows principal)
        vm.startPrank(lender);
        lendToken.approve(address(pool), 100 ether);
        uint256 offerId =
            pool.createLendingOffer(address(lendToken), 100 ether, 600, 90 days, address(collateralToken), 15000);
        vm.stopPrank();

        // borrower accepts offer by providing collateral
        vm.startPrank(borrower);
        collateralToken.approve(address(pool), 150 ether);
        uint256 loanId = pool.acceptOfferByBorrower(offerId, 150 ether);

        // inspect loan tuple returned by public accessor
        (,,,,, uint256 principal,, uint256 lenderTokenId, uint256 borrowerTokenId,,) = pool.getLoan(loanId);
        assertEq(principal, 100 ether);
        // check that borrower received principal
        assertEq(lendToken.balanceOf(borrower), 100 ether);

        // repay full
        uint256 interest = pool.accruedInterest(loanId);
        uint256 total = 100 ether + interest;
        // borrower needs to have lendToken to repay; mint to borrower
        lendToken.mint(borrower, total);
        lendToken.approve(address(pool), total);

        pool.repayFull(loanId);

        // after repay, loan should be marked repaid
        (,,,,, uint256 princ2,, uint256 ltid, uint256 btid,,) = pool.getLoan(loanId);
        // loan should be repaid (we'll check via principal being unchanged and owner fees/other side)
        (,,,,,,,,, bool repaid2,) = pool.getLoan(loanId);
        assertTrue(repaid2);

        // ensure NFTs were burned: ownerOf should revert
        vm.expectRevert();
        nft.ownerOf(ltid);
        vm.expectRevert();
        nft.ownerOf(btid);

        vm.stopPrank();
    }

    // helpers removed; use public accessor destructuring in tests
}
