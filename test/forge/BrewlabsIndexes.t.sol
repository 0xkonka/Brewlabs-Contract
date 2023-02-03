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
        _paths[0][1] = 0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7;
        _paths[1][0] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        _paths[1][1] = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();
        nft = new BrewlabsIndexesNft();
        indexes = new BrewlabsIndexes();
        indexes.initialize(
            [IERC20(0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7), IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)],
            IERC721(nft),
            _router,
            _paths
        );

        nft.setMinterRole(address(indexes), true);
    }

    function test_buyTokens() public {
        vm.startPrank(address(0x1));
        uint256 amount = 0.5 ether;
        vm.deal(address(0x1), 10 ether);
        vm.stopPrank();
    }
}
