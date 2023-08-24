// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBrewlabsAggregator} from "../libs/IBrewlabsAggregator.sol";

contract BrewlabsIndexData {
    uint256 private FEE_DENOMINATOR = 10000;

    constructor() {}

    function precomputeZapIn(
        address _aggregator,
        address _token,
        uint256 _amount,
        IERC20[] memory _tokens,
        uint256[] memory _percents,
        uint256 _gasPrice
    ) external view returns (IBrewlabsAggregator.FormattedOffer[] memory queries) {
        address WNATIVE = IBrewlabsAggregator(_aggregator).WNATIVE();
        uint256 NUM_TOKENS = _tokens.length;

        queries = new IBrewlabsAggregator.FormattedOffer[](NUM_TOKENS + 1);

        uint256 ethAmount = _amount;
        if (_token != address(0x0)) {
            queries[0] = IBrewlabsAggregator(_aggregator).findBestPathWithGas(_amount, _token, WNATIVE, 3, _gasPrice);
            uint256[] memory _amounts = queries[0].amounts;
            ethAmount = _amounts[_amounts.length - 1];
        }

        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            if (i >= _percents.length) break;

            uint256 amountIn = (ethAmount * _percents[i]) / FEE_DENOMINATOR;
            if (amountIn == 0 || address(_tokens[i]) == WNATIVE) continue;

            queries[i + 1] = IBrewlabsAggregator(_aggregator).findBestPathWithGas(
                amountIn, WNATIVE, address(_tokens[i]), 3, _gasPrice
            );
        }
    }

    function precomputeZapOut(
        address _aggregator,
        IERC20[] memory _tokens,
        uint256[] memory amounts,
        address _token,
        uint256 _gasPrice
    ) external view returns (IBrewlabsAggregator.FormattedOffer[] memory queries) {
        address WNATIVE = IBrewlabsAggregator(_aggregator).WNATIVE();
        uint256 NUM_TOKENS = _tokens.length;

        queries = new IBrewlabsAggregator.FormattedOffer[](NUM_TOKENS + 1);

        uint256 ethAmount = 0;
        for (uint256 i = 0; i < NUM_TOKENS; i++) {
            if (amounts[i] == 0) continue;
            if (address(_tokens[i]) == WNATIVE) {
                ethAmount += amounts[i];
                continue;
            }

            queries[i] = IBrewlabsAggregator(_aggregator).findBestPathWithGas(
                amounts[i], address(_tokens[i]), WNATIVE, 3, _gasPrice
            );
            uint256[] memory _amounts = queries[i].amounts;
            ethAmount += _amounts[_amounts.length - 1];
        }

        if (_token != address(0x0)) {
            queries[NUM_TOKENS] =
                IBrewlabsAggregator(_aggregator).findBestPathWithGas(ethAmount, WNATIVE, _token, 3, _gasPrice);
        }
    }

    function expectedEth(address _aggregator, IERC20[] memory _tokens, uint256[] memory _amounts)
        external
        view
        returns (uint256 amountOut)
    {
        address WNATIVE = IBrewlabsAggregator(_aggregator).WNATIVE();
        uint256 NUM_TOKENS = _tokens.length;

        uint256 aggregatorFee = IBrewlabsAggregator(_aggregator).BREWS_FEE();

        IBrewlabsAggregator.FormattedOffer memory query;
        for (uint8 i = 0; i < NUM_TOKENS; i++) {
            if (_amounts[i] == 0) continue;

            if (address(_tokens[i]) == WNATIVE) {
                amountOut += _amounts[i];
            } else {
                query = IBrewlabsAggregator(_aggregator).findBestPath(_amounts[i], address(_tokens[i]), WNATIVE, 3);
                uint256 _amountOut = query.amounts[query.amounts.length - 1];
                if (aggregatorFee > 0) _amountOut = _amountOut * (FEE_DENOMINATOR - aggregatorFee) / FEE_DENOMINATOR;
                amountOut += _amountOut;
            }
        }
    }
}
