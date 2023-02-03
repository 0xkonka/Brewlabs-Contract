// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// import "forge-std/console.sol";       // use like hardhat console.log
import {MockErc20} from "../../contracts/mocks/MockErc20.sol";
import {BrewlabsIndexes, IBrewlabsIndexesNft, IERC20} from "../../contracts/BrewlabsIndexes.sol";
import {BrewlabsIndexesNft, IERC721} from "../../contracts/BrewlabsIndexesNft.sol";
import {Utils} from "./utils/Utils.sol";

contract BrewlabsIndexesTest is Test {
    BrewlabsIndexes internal indexes;
    BrewlabsIndexesNft internal nft;
    Utils internal utils;
    
    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    function setUp() public {
        address _router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

        address[][2] memory _paths;
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        _paths[0][1] = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
        _paths[1][0] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        _paths[1][1] = 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47;

        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();
        nft = new BrewlabsIndexesNft();
        indexes = new BrewlabsIndexes();

        indexes.initialize(
            [IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8), IERC20(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47)],
            IERC721(nft),
            _router,
            _paths
        );
        nft.setMinterRole(address(indexes), true);
    }

    function test_buyTokens() public {
        vm.deal(address(0x1), 10 ether);
        vm.startPrank(address(0x1));
        
        IERC20 token0 = indexes.tokens(0);
        IERC20 token1 = indexes.tokens(1);
        uint256 amount = 0.5 ether;
        indexes.buyTokens{value: amount}([uint256(5000), 5000]);
        emit log_named_uint('balance of token0', token0.balanceOf(address(indexes)));
        emit log_named_uint('balance of token1', token1.balanceOf(address(indexes)));
        vm.stopPrank();
    }
}
