// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This treasury contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./libs/IUniRouter02.sol";

contract BrewlabsRevenue is Ownable {
    using SafeERC20 for IERC20;

    // Whether it is initialized
    bool private isInitialized;

    address public walletA;
    address public walletB;

    uint256 public walletARate = 3000;
    uint256 public saleRate = 10000; // 100%

    // swap router and path, slipPage
    address public uniRouterAddress;
    address[] public swapPath;

    event TokenBuyBack(uint256 amountToken);
    event DividendRateUpdated(uint256 rate1, uint256 rate2);
    event SaleRateUpdated(uint256 rate);
    event SetSwapConfig(address router, address[] path);

    constructor() {}

    /**
     * @notice Initialize the contract
     * @param _walletA: contract A
     * @param _walletB: contract B
     * @param _uniRouter: uniswap router address for swap tokens
     * @param _swapPath: swap path to buy Token
     */
    function initialize(address _walletA, address _walletB, address _uniRouter, address[] memory _swapPath)
        external
        onlyOwner
    {
        require(!isInitialized, "Already initialized");
        require(IUniRouter01(_uniRouter).WETH() == _swapPath[0], "invalid router");

        // Make this contract initialized
        isInitialized = true;

        walletA = _walletA;
        walletB = _walletB;
        uniRouterAddress = _uniRouter;
        swapPath = _swapPath;
    }

    /**
     * @notice Buy token from BNB
     */
    function buyBack() external onlyOwner {
        if (swapPath.length < 2) return;

        address tokenB = swapPath[swapPath.length - 1];

        uint256 swapAmt = address(this).balance;
        swapAmt = swapAmt * saleRate / 10000;

        if (swapAmt > 0) {
            _safeSwapEth(swapAmt, swapPath, address(this));

            uint256 tokenBal = IERC20(tokenB).balanceOf(address(this));
            uint256 tokenAmt = tokenBal * walletARate / 10000;

            IERC20(tokenB).transfer(walletA, tokenAmt);
            IERC20(tokenB).transfer(walletB, tokenBal - tokenAmt);
        }
    }

    /**
     * @notice Set sale rate
     * @param _rate: percentage in point
     */
    function setSaleRate(uint256 _rate) external onlyOwner {
        require(_rate < 10000, "Invalid percentage");

        saleRate = _rate;
        emit SaleRateUpdated(_rate);
    }

    /**
     * @notice Set dividend rate
     * @param _aRate: percentage in point
     */
    function setDividendRate(uint256 _aRate) external onlyOwner {
        require(_aRate <= 10000, "Invalid percentage");

        walletARate = _aRate;
        emit DividendRateUpdated(walletARate, 10000 - _aRate);
    }

    function setWalletA(address _walletA) external onlyOwner {
        require(_walletA != address(0x0), "invalid address");
        walletA = _walletA;
    }

    function setWalletB(address _walletB) external onlyOwner {
        require(_walletB != address(0x0), "invalid address");
        walletB = _walletB;
    }

    /**
     * @notice Set buyback wallet of farm contract
     * @param _uniRouter: dex router address
     * @param _path: bnb-token swap path
     */
    function setSwapSettings(address _uniRouter, address[] memory _path) external onlyOwner {
        require(IUniRouter01(_uniRouter).WETH() == _path[0], "invalid router");
        uniRouterAddress = _uniRouter;
        swapPath = _path;

        emit SetSwapConfig(_uniRouter, _path);
    }

    /**
     * @notice It allows the admin to recover wrong tokens sent to the contract
     * @param _token: the address of the token to withdraw
     * @dev This function is only callable by admin.
     */
    function rescueToken(address _token) external onlyOwner {
        if (_token == address(0x0)) {
            uint256 _tokenAmount = address(this).balance;
            payable(msg.sender).transfer(_tokenAmount);
        } else {
            uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
            IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
        }
    }

    /**
     *
     * Internal Methods
     *
     */
    /*
     * @notice get token from ETH via swap.
     */
    function _safeSwapEth(uint256 _amountIn, address[] memory _path, address _to) internal {
        IUniRouter02(uniRouterAddress).swapExactETHForTokensSupportingFeeOnTransferTokens{value: _amountIn}(
            0, _path, _to, block.timestamp + 600
        );
    }

    receive() external payable {}
}
