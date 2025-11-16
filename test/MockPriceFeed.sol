// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockPriceFeed {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function latestAnswer() external view returns (int256) {
        return _price;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}
