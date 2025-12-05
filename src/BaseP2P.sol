// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title BaseP2P
 * @author BaseFi Protocol
 * @notice Small base contract exposing SafeERC20 helpers for P2P protocol contracts.
 * @dev Provides internal wrappers around SafeERC20 to standardize token transfers.
 */
contract BaseP2P is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @notice Initializes the ownership for inheriting contracts.
     * @dev Ownable in OZ v5 accepts the initial owner in its constructor.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Safely transfers `amount` of `token` from `from` to `to` using SafeERC20.
     * @param token The ERC20 token to transfer.
     * @param from The address to pull tokens from.
     * @param to The recipient address to send tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        token.safeTransferFrom(from, to, amount);
    }

    /**
     * @notice Safely transfers `amount` of `token` to `to` using SafeERC20.
     * @param token The ERC20 token to transfer.
     * @param to The recipient address to send tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        token.safeTransfer(to, amount);
    }
}
