// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    int256 private _answer;
    uint8 private _decimals;

    constructor(int256 initialAnswer, uint8 decimals_) {
        _answer = initialAnswer;
        _decimals = decimals_;
    }

    function latestAnswer() external view override returns (int256) {
        return _answer;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }
}
