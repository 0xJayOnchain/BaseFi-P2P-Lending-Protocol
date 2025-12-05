// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockFeeOnTransferERC20
/// @author BaseFi P2P Lending Protocol
/// @notice ERC20 that charges a fee on transfer, reducing the received amount.
contract MockFeeOnTransferERC20 is ERC20 {
    /// @notice Fee in basis points (e.g., 100 = 1%)
    uint256 public feeBps; // e.g., 100 = 1%

    /// @notice Constructor to create a fee-on-transfer ERC20 token
    /// @param name_ The name of the token
    /// @param symbol_ The symbol of the token
    /// @param decimals_ The number of decimals for the token
    /// @param feeBps_ The fee in basis points charged on each transfer
    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 feeBps_) ERC20(name_, symbol_) {
        _decimals = decimals_;
        feeBps = feeBps_;
    }

    uint8 private _decimals;

    /// @notice Returns the number of decimals used for token amounts
    /// @return The number of decimals
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mints new tokens for testing
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Internal function to handle transfers with fee deduction
    /// @param from The address sending tokens
    /// @param to The address receiving tokens
    /// @param value The amount of tokens being transferred
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 0) {
            uint256 fee = (value * feeBps) / 10000;
            uint256 sendAmount = value - fee;
            // debit full value from sender
            super._update(from, address(0), fee); // burn fee for simplicity
            super._update(from, to, sendAmount);
        } else {
            super._update(from, to, value);
        }
    }
}
