// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libs/Babylonian.sol";
import "./libs/FixedPoint.sol";
import "./libs/UniswapV2OracleLibrary.sol";
import "./libs/IUniPair.sol";
import "./libs/Epoch.sol";

// fixed window oracle that recomputes the average price for the entire period once every period
// note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period
contract BrewlabsTwapOracle is Epoch {
    using FixedPoint for *;

    /* ========== STATE VARIABLES ========== */

    // uniswap
    address public token0;
    address public token1;
    IUniswapV2Pair public pair;

    // oracle
    uint32 public blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);

    /* ========== CONSTRUCTOR ========== */
    constructor(IUniswapV2Pair _pair, uint256 _period, uint256 _startTime) Epoch(_period, _startTime, 0) {
        pair = _pair;
        token0 = pair.token0();
        token1 = pair.token1();
        price0CumulativeLast = pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "BrewlabsTwapOracle: NO_RESERVES"); // ensure that there's liquidity in the pair
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    /**
     * @dev Updates 1-day EMA price from Uniswap.
     */
    function update() external checkEpoch {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed == 0) {
            // prevent divided by zero
            return;
        }

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;

        emit Updated(price0Cumulative, price1Cumulative);
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address _token, uint256 _amountIn) external view returns (uint144 amountOut) {
        if (_token == token0) {
            amountOut = price0Average.mul(_amountIn).decode144();
        } else {
            require(_token == token1, "BrewlabsTwapOracle: INVALID_TOKEN");
            amountOut = price1Average.mul(_amountIn).decode144();
        }
    }

    function twap(address _token, uint256 _amountIn) external view returns (uint144 _amountOut) {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (_token == token0) {
            if (timeElapsed == 0) {
                _amountOut = price0Average.mul(_amountIn).decode144();
            } else {
                _amountOut = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)).mul(
                    _amountIn
                ).decode144();
            }
        } else if (_token == token1) {
            if (timeElapsed == 0) {
                _amountOut = price1Average.mul(_amountIn).decode144();
            } else {
                _amountOut = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)).mul(
                    _amountIn
                ).decode144();
            }
        }
    }
}
