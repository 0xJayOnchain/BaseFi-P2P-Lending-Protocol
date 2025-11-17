// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title BaseP2P
 * @dev Small base contract exposing SafeERC20 helpers for P2P protocol contracts.
 */
contract BaseP2P is Ownable {
    using SafeERC20 for IERC20;

    constructor() Ownable(msg.sender) {}

    function _safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        token.safeTransferFrom(from, to, amount);
    }

    function _safeTransfer(IERC20 token, address to, uint256 amount) internal {
        token.safeTransfer(to, amount);
    }
}
