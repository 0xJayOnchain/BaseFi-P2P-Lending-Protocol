// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @notice ERC20 that charges a fee on transfer, reducing the received amount.
contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public feeBps; // e.g., 100 = 1%

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 feeBps_) ERC20(name_, symbol_) {
        _decimals = decimals_;
        feeBps = feeBps_;
    }

    uint8 private _decimals;
    function decimals() public view override returns (uint8) { return _decimals; }

    function mint(address to, uint256 amount) external { _mint(to, amount); }

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
