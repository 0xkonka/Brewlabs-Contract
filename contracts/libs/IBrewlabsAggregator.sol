// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrewlabsAggregator {
    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address[] adapters;
    }

    function findBestPath(uint256 _amountIn, address _tokenIn, address _tokenOut, uint256 _maxSteps)
        external
        view
        returns (uint256[] memory amounts, address[] memory adapters, address[] memory path, uint256 gasEstimate);

    function swapNoSplit(Trade memory _trade, address _to) external;
    function swapNoSplitFromETH(Trade memory _trade, address _to) external payable;
    function swapNoSplitToETH(Trade memory _trade, address _to) external;
}
