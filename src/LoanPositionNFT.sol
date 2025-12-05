// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./interfaces/ILoanPositionNFT.sol";

/**
 * @title LoanPositionNFT
 * @author BaseFi P2P Lending Protocol
 * @notice ERC721 representing loan positions (lender/borrower). Minting is restricted to MINTER_ROLE.
 * @dev ERC721 representing loan positions (lender/borrower). Minting is restricted to MINTER_ROLE.
 */
contract LoanPositionNFT is ERC721, AccessControl, ILoanPositionNFT {
    /// @notice Role identifier for addresses allowed to mint and burn NFTs
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _nextTokenId = 1;

    mapping(uint256 => uint256) private _loanOf;
    mapping(uint256 => Role) private _roleOf;

    /// @notice Constructor initializes the NFT contract with name and symbol
    /// @param name_ The name of the NFT collection
    /// @param symbol_ The symbol of the NFT collection
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Checks if the contract supports a specific interface
    /// @param interfaceId The interface identifier to check
    /// @return True if the interface is supported
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    /// @notice Mints a new position NFT for a loan
    /// @param to The address to receive the NFT
    /// @param loanId The loan ID this NFT represents
    /// @param role The role (LENDER or BORROWER) this NFT represents
    /// @return The minted token ID
    function mint(address to, uint256 loanId, Role role) external override returns (uint256) {
        require(hasRole(MINTER_ROLE, msg.sender), "not minter");
        uint256 tid = _nextTokenId++;
        _loanOf[tid] = loanId;
        _roleOf[tid] = role;
        _safeMint(to, tid);
        return tid;
    }

    /// @notice Burns a position NFT
    /// @param tokenId The token ID to burn
    function burn(uint256 tokenId) external override {
        require(hasRole(MINTER_ROLE, msg.sender), "not minter");
        _burn(tokenId);
        delete _loanOf[tokenId];
        delete _roleOf[tokenId];
    }

    /// @notice Gets the loan ID associated with a token
    /// @param tokenId The token ID to query
    /// @return The loan ID
    function loanOfToken(uint256 tokenId) external view override returns (uint256) {
        return _loanOf[tokenId];
    }

    /// @notice Gets the role (LENDER or BORROWER) associated with a token
    /// @param tokenId The token ID to query
    /// @return The role of the token
    function roleOfToken(uint256 tokenId) external view override returns (Role) {
        return _roleOf[tokenId];
    }

    // Expose ownerOf through the interface and resolve multiple inheritance
    /// @notice Gets the owner of a token
    /// @param tokenId The token ID to query
    /// @return The address of the token owner
    function ownerOf(uint256 tokenId) public view override(ERC721, ILoanPositionNFT) returns (address) {
        return ERC721.ownerOf(tokenId);
    }
}
