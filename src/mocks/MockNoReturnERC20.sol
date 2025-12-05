// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MockNoReturnERC20
/// @author BaseFi P2P Lending Protocol
/// @notice Minimal ERC20-like token that does not return bool in transfer/transferFrom/approve.
contract MockNoReturnERC20 is IERC20 {
    /// @notice The name of the token
    string public name = "NoReturn";
    /// @notice The symbol of the token
    string public symbol = "NRT";
    /// @notice The number of decimals for the token
    uint8 public decimals = 18;

    /// @notice Mapping of account balances
    mapping(address => uint256) public override balanceOf;
    /// @notice Mapping of allowances
    mapping(address => mapping(address => uint256)) public override allowance;
    /// @notice Total supply of tokens
    uint256 public override totalSupply;

    /// @notice Mints new tokens for testing
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        // no return
    }

    /// @notice Transfers tokens from the caller to another address
    /// @param to The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        // return value ignored by SafeERC20, but we return true for interface compliance
        return true;
    }

    /// @notice Approves another address to spend tokens on behalf of the caller
    /// @param spender The address authorized to spend tokens
    /// @param amount The amount of tokens the spender can transfer
    /// @return success True if the approval succeeded
    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @notice Transfers tokens from one address to another using allowance
    /// @param from The address to transfer tokens from
    /// @param to The address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @return success True if the transfer succeeded
    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        allowance[from][msg.sender] = allowed - amount;
        _transfer(from, to, amount);
        return true;
    }

    /// @notice Internal function to handle token transfers
    /// @param from The address sending tokens
    /// @param to The address receiving tokens
    /// @param amount The amount of tokens being transferred
    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}
