// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILoanPositionNFT {
    enum Role {
        LENDER,
        BORROWER
    }

    function mint(address to, uint256 loanId, Role role) external returns (uint256);
    function burn(uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
    function loanOfToken(uint256 tokenId) external view returns (uint256);
    function roleOfToken(uint256 tokenId) external view returns (Role);
}
