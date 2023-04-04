pragma solidity 0.8.13;

interface IRouter {
    struct route {
        address from;
        address to;
        bool stable;
    }
    function pairFor(address tokenA, address tokenB, bool stable) external view returns (address pair);
    function getAmountOut(
        uint256 amountIn,
        address tokenIn,
        address tokenOut
    ) external view returns (uint256 amount, bool stable);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
