// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import "./interfaces/ILoanPositionNFT.sol";

/**
 * @title LoanPositionNFT
 * @dev ERC721 representing loan positions (lender/borrower). Minting is restricted to MINTER_ROLE.
 */
contract LoanPositionNFT is ERC721, AccessControl, ILoanPositionNFT {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 private _nextTokenId = 1;

    mapping(uint256 => uint256) private _loanOf;
    mapping(uint256 => Role) private _roleOf;

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || AccessControl.supportsInterface(interfaceId);
    }

    function mint(address to, uint256 loanId, Role role) external override returns (uint256) {
        require(hasRole(MINTER_ROLE, msg.sender), "not minter");
        uint256 tid = _nextTokenId++;
        _loanOf[tid] = loanId;
        _roleOf[tid] = role;
        _safeMint(to, tid);
        return tid;
    }

    function burn(uint256 tokenId) external override {
        require(hasRole(MINTER_ROLE, msg.sender), "not minter");
        _burn(tokenId);
        delete _loanOf[tokenId];
        delete _roleOf[tokenId];
    }

    function loanOfToken(uint256 tokenId) external view override returns (uint256) {
        return _loanOf[tokenId];
    }

    function roleOfToken(uint256 tokenId) external view override returns (Role) {
        return _roleOf[tokenId];
    }

    // Expose ownerOf through the interface and resolve multiple inheritance
    function ownerOf(uint256 tokenId) public view override(ERC721, ILoanPositionNFT) returns (address) {
        return ERC721.ownerOf(tokenId);
    }
}
