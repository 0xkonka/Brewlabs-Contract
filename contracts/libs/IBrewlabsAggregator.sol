// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrewlabsAggregator {
    struct Trade {
        uint256 amountIn;
        uint256 amountOut;
        address[] path;
        address[] adapters;
    }

    struct FormattedOffer {
        uint256[] amounts;
        address[] adapters;
        address[] path;
        uint256 gasEstimate;
    }

    function WNATIVE() external view returns (address);
    function BREWS_FEE() external view returns (uint256);
    function findBestPath(uint256 _amountIn, address _tokenIn, address _tokenOut, uint256 _maxSteps)
        external
        view
        returns (FormattedOffer memory);
    function findBestPathWithGas(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut,
        uint256 _maxSteps,
        uint256 _gasPrice
    ) external view returns (FormattedOffer memory);

    function swapNoSplit(Trade memory _trade, address _to, uint256 _deadline) external;
    function swapNoSplitFromETH(Trade memory _trade, address _to, uint256 _deadline) external payable;
    function swapNoSplitToETH(Trade memory _trade, address _to, uint256 _deadline) external;
}
