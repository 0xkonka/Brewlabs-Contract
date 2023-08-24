// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsTreasury, IBrewlabsAggregator, IERC20} from "../../contracts/BrewlabsTreasury.sol";
import {Utils} from "./utils/Utils.sol";

contract BrewlabsTreasuryTest is Test {
    address swapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address brewlabsAggregator = 0x260C865B96C6e70A25228635F8123C3A7ab0b4e2;
    address internal WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address internal BREWLABS = 0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7;

    BrewlabsTreasury internal treasury;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();

        treasury = new BrewlabsTreasury();
        treasury.initialize(IERC20(BREWLABS), BUSD, swapRouter);
    }

    function test_buyBack() public {
        vm.deal(address(treasury), 1 ether);

        uint256 _amountIn = 1 ether * treasury.buybackRate() / 10000;
        emit log_address(address(treasury.swapAggregator()));
        IBrewlabsAggregator.FormattedOffer memory query =
            treasury.swapAggregator().findBestPath(_amountIn, WBNB, BREWLABS, 2);
        emit log_named_uint("expected amount", query.amounts[query.amounts.length - 1]);

        treasury.buyBack();
        uint256 tokenBalance = IERC20(BREWLABS).balanceOf(address(treasury));
        emit log_named_uint("received amount", tokenBalance);
    }

    receive() external payable {}
}
