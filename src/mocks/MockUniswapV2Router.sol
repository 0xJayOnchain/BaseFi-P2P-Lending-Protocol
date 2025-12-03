// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockUniswapV2Router {
    using SafeERC20 for IERC20;

    // swapExactTokensForTokens: transfers amountIn of tokenIn from msg.sender, then sends amountOutMin of tokenOut to 'to'.
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(block.timestamp <= deadline, "deadline");
        require(path.length >= 2, "bad path");
        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // take tokenIn from caller (pool)
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // send tokenOut from router to recipient; router must be pre-funded in tests
        IERC20(tokenOut).safeTransfer(to, amountOutMin);

        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOutMin;
        return amounts;
    }
}
