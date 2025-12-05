// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title ILoanPositionNFT
/// @author BaseFi P2P Lending Protocol
/// @notice Interface for loan position NFTs representing lender and borrower positions
interface ILoanPositionNFT {
    enum Role {
        LENDER,
        BORROWER
    }

    /// @notice Mints a new position NFT for a loan
    /// @param to The address to receive the NFT
    /// @param loanId The loan ID this NFT represents
    /// @param role The role (LENDER or BORROWER) this NFT represents
    /// @return The minted token ID
    function mint(address to, uint256 loanId, Role role) external returns (uint256);

    /// @notice Burns a position NFT
    /// @param tokenId The token ID to burn
    function burn(uint256 tokenId) external;

    /// @notice Gets the owner of a token
    /// @param tokenId The token ID to query
    /// @return The address of the token owner
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @notice Gets the loan ID associated with a token
    /// @param tokenId The token ID to query
    /// @return The loan ID
    function loanOfToken(uint256 tokenId) external view returns (uint256);

    /// @notice Gets the role (LENDER or BORROWER) associated with a token
    /// @param tokenId The token ID to query
    /// @return The role of the token
    function roleOfToken(uint256 tokenId) external view returns (Role);
}
