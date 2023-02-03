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

    function setUp() public {
        utils = new Utils();

        nft = new BrewlabsIndexesNft();
        indexes = new BrewlabsIndexes();

        address _router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
        address[2][] memory _paths;
        _paths[0] = [address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c), 0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7];
        _paths[1] = [address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c), 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56];
        indexes.initialize(
            [IERC20(0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7), IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56)],
            IERC721(nft),
            _router,
            _paths
        );

        nft.setMinterRole(address(indexes), true);
    }
}
