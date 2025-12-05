// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockUniswapV2Router
/// @author BaseFi P2P Lending Protocol
/// @notice Mock Uniswap V2 Router for testing token swaps
contract MockUniswapV2Router {
    using SafeERC20 for IERC20;

    /// @notice Swaps exact tokens for tokens along a specified path
    /// @param amountIn The amount of input tokens to swap
    /// @param amountOutMin The minimum amount of output tokens expected
    /// @param path The token swap path (array of token addresses)
    /// @param to The address to receive the output tokens
    /// @param deadline The timestamp by which the swap must be executed
    /// @return amounts Array of amounts for each step in the swap path
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(block.timestamp <= deadline, "deadline");
        require(path.length >= 2, "bad path");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // take tokenIn from caller (pool)
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // send tokenOut from router to recipient; router must be pre-funded in tests
        IERC20(tokenOut).safeTransfer(to, amountOutMin);

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOutMin;
        return amounts;
    }
}
