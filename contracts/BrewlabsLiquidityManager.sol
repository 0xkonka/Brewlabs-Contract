// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import {IUniV2Factory} from "./libs/IUniFactory.sol";
import {IUniRouter02} from "./libs/IUniRouter02.sol";
import {IWETH} from "./libs/IWETH.sol";

contract BrewlabsLiquidityManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public fee = 100; // 1%
    address public treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
    address public walletA = 0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F;

    uint256 public slippageFactor = 9500; // 5% default slippage tolerance
    uint256 public constant slippageFactorUL = 8000;
    uint256 public constant FEE_DENOMINATOR = 10000;

    uint256 public buyBackLimit = 0.1 ether;

    event WalletAUpdated(address addr);
    event FeeUpdated(uint256 fee);
    event BuyBackLimitUpdated(uint256 limit);
    event AdminTokenRecovered(address tokenRecovered, uint256 amount);

    constructor() {}

    function addLiquidity(
        address router,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 slipPage
    ) external payable nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amount0 > 0 && amount1 > 0, "amount is zero");
        require(token0 != token1, "cannot use same token for pair");
        require(slipPage < FEE_DENOMINATOR, "slippage cannot exceed 100%");

        uint256 beforeAmt = IERC20(token0).balanceOf(address(this));
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        uint256 token0Amt = IERC20(token0).balanceOf(address(this)) - beforeAmt;
        token0Amt = token0Amt * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;

        beforeAmt = IERC20(token1).balanceOf(address(this));
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
        uint256 token1Amt = IERC20(token1).balanceOf(address(this)) - beforeAmt;
        token1Amt = token1Amt * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;

        (amountA, amountB, liquidity) = _addLiquidity(router, token0, token1, token0Amt, token1Amt, slipPage);

        token0Amt = IERC20(token0).balanceOf(address(this));
        token1Amt = IERC20(token1).balanceOf(address(this));
        IERC20(token0).safeTransfer(walletA, token0Amt);
        IERC20(token1).safeTransfer(walletA, token1Amt);
    }

    function _addLiquidity(
        address router,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 slipPage
    ) internal returns (uint256, uint256, uint256) {
        IERC20(token0).safeApprove(router, 0);
        IERC20(token1).safeApprove(router, 0);
        IERC20(token0).safeIncreaseAllowance(router, amount0);
        IERC20(token1).safeIncreaseAllowance(router, amount1);

        return IUniRouter02(router).addLiquidity(
            token0,
            token1,
            amount0,
            amount1,
            amount0 * (FEE_DENOMINATOR - slipPage) / FEE_DENOMINATOR,
            amount1 * (FEE_DENOMINATOR - slipPage) / FEE_DENOMINATOR,
            msg.sender,
            block.timestamp + 600
        );
    }

    function addLiquidityETH(address router, address token, uint256 amount, uint256 slipPage)
        external
        payable
        nonReentrant
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        require(amount > 0, "amount is zero");
        require(msg.value > 0, "amount is zero");
        require(slipPage < FEE_DENOMINATOR, "slippage cannot exceed 100%");

        uint256 beforeAmt = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 tokenAmt = IERC20(token).balanceOf(address(this)) - beforeAmt;
        tokenAmt = tokenAmt * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;

        uint256 ethAmt = msg.value;
        ethAmt = ethAmt * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;

        IERC20(token).safeApprove(router, 0);
        IERC20(token).safeIncreaseAllowance(router, tokenAmt);
        (amountToken, amountETH, liquidity) = _addLiquidityETH(router, token, tokenAmt, ethAmt, slipPage);

        tokenAmt = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(walletA, tokenAmt);

        ethAmt = address(this).balance;
        payable(treasury).transfer(ethAmt);
    }

    function _addLiquidityETH(address router, address token, uint256 tokenAmt, uint256 ethAmt, uint256 slipPage)
        internal
        returns (uint256, uint256, uint256)
    {
        IERC20(token).safeApprove(router, 0);
        IERC20(token).safeIncreaseAllowance(router, tokenAmt);

        return IUniRouter02(router).addLiquidityETH{value: ethAmt}(
            token,
            tokenAmt,
            tokenAmt * (FEE_DENOMINATOR - slipPage) / FEE_DENOMINATOR,
            ethAmt * (FEE_DENOMINATOR - slipPage) / FEE_DENOMINATOR,
            msg.sender,
            block.timestamp + 600
        );
    }

    function removeLiquidity(address router, address token0, address token1, uint256 amount)
        external
        nonReentrant
        returns (uint256 amountA, uint256 amountB)
    {
        require(amount > 0, "amount is zero");

        address pair = _getPair(router, token0, token1);
        require(pair != address(0), "invalid liquidity");

        IERC20(pair).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(pair).safeIncreaseAllowance(router, amount);

        uint256 beforeAmt0 = IERC20(token0).balanceOf(address(this));
        uint256 beforeAmt1 = IERC20(token1).balanceOf(address(this));
        IUniRouter02(router).removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp + 600);

        amountA = IERC20(token0).balanceOf(address(this)) - beforeAmt0;
        amountB = IERC20(token1).balanceOf(address(this)) - beforeAmt1;
        IERC20(token0).safeTransfer(walletA, amountA * fee / FEE_DENOMINATOR);
        IERC20(token1).safeTransfer(walletA, amountB * fee / FEE_DENOMINATOR);

        amountA = amountA * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        amountB = amountB * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        IERC20(token0).safeTransfer(msg.sender, amountA);
        IERC20(token1).safeTransfer(msg.sender, amountB);
    }

    function removeLiquidityETH(address router, address token, uint256 amount)
        external
        nonReentrant
        returns (uint256 amountToken, uint256 amountETH)
    {
        require(amount > 0, "amount is zero");

        address weth = IUniRouter02(router).WETH();
        address pair = _getPair(router, token, weth);
        require(pair != address(0), "invalid liquidity");

        IERC20(pair).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(pair).safeIncreaseAllowance(router, amount);

        uint256 beforeAmt0 = IERC20(token).balanceOf(address(this));
        uint256 beforeAmt1 = address(this).balance;
        IUniRouter02(router).removeLiquidityETH(token, amount, 0, 0, address(this), block.timestamp + 600);

        amountToken = IERC20(token).balanceOf(address(this)) - beforeAmt0;
        amountETH = address(this).balance - beforeAmt1;
        IERC20(token).safeTransfer(walletA, amountToken * fee / FEE_DENOMINATOR);
        payable(treasury).transfer(amountETH * fee / FEE_DENOMINATOR);

        amountToken = amountToken * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        amountETH = amountETH * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        IERC20(token).safeTransfer(msg.sender, amountToken);
        payable(msg.sender).transfer(amountETH);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(address router, address token, uint256 amount)
        external
        nonReentrant
        returns (uint256 amountETH)
    {
        require(amount > 0, "amount is zero");

        address weth = IUniRouter02(router).WETH();
        address pair = _getPair(router, token, weth);
        require(pair != address(0), "invalid liquidity");

        IERC20(pair).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(pair).safeIncreaseAllowance(router, amount);

        uint256 beforeAmt0 = IERC20(token).balanceOf(address(this));
        uint256 beforeAmt1 = address(this).balance;
        IUniRouter02(router).removeLiquidityETHSupportingFeeOnTransferTokens(
            token, amount, 0, 0, address(this), block.timestamp + 600
        );

        uint256 amountToken = IERC20(token).balanceOf(address(this)) - beforeAmt0;
        amountETH = address(this).balance - beforeAmt1;
        IERC20(token).safeTransfer(walletA, amountToken * fee / FEE_DENOMINATOR);
        payable(treasury).transfer(amountETH * fee / FEE_DENOMINATOR);

        amountToken = amountToken * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        amountETH = amountETH * (FEE_DENOMINATOR - fee) / FEE_DENOMINATOR;
        IERC20(token).safeTransfer(msg.sender, amountToken);
        payable(msg.sender).transfer(amountETH);
    }

    function buyBack(address router, address[] memory wethToBrewsPath) internal {
        uint256 ethAmt = address(this).balance;

        if (ethAmt > buyBackLimit) {
            _safeSwapWeth(router, ethAmt, wethToBrewsPath, treasury);
        }
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0x0), "Invalid address");
        treasury = _treasury;
    }

    function updateWalletA(address _walletA) external onlyOwner {
        require(_walletA != address(0x0) || _walletA != walletA, "Invalid address");

        walletA = _walletA;
        emit WalletAUpdated(_walletA);
    }

    function updateFee(uint256 _fee) external onlyOwner {
        require(_fee < 2000, "fee cannot exceed 20%");

        fee = _fee;
        emit FeeUpdated(_fee);
    }

    function updateBuyBackLimit(uint256 _limit) external onlyOwner {
        require(_limit > 0, "Invalid amount");

        buyBackLimit = _limit;
        emit BuyBackLimitUpdated(_limit);
    }

    function _getPair(address router, address token0, address token1) internal view returns (address) {
        address factory = IUniRouter02(router).factory();
        return IUniV2Factory(factory).getPair(token0, token1);
    }

    function _safeSwapWeth(address router, uint256 _amountIn, address[] memory _path, address _to) internal {
        uint256[] memory amounts = IUniRouter02(router).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length - 1];

        IUniRouter02(router).swapExactETHForTokens{value: _amountIn}(
            amountOut * slippageFactor / FEE_DENOMINATOR, _path, _to, block.timestamp + 600
        );
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param token: the address of the token to withdraw
     * @param amount: the number of tokens to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueTokens(address token, uint256 amount) external onlyOwner {
        if (token == address(0x0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(token).safeTransfer(address(msg.sender), amount);
        }

        emit AdminTokenRecovered(token, amount);
    }

    receive() external payable {}
}
