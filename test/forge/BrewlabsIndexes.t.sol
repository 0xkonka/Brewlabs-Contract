// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
// import "forge-std/console.sol";       // use like hardhat console.log
import {MockErc20} from "../../contracts/mocks/MockErc20.sol";
import {BrewlabsIndexes, IBrewlabsIndexesNft, IERC20} from "../../contracts/BrewlabsIndexes.sol";
import {BrewlabsIndexesNft, IERC721} from "../../contracts/BrewlabsIndexesNft.sol";
import {Utils} from "./utils/Utils.sol";

contract BrewlabsIndexesTest is Test {
    IERC20 internal token0 = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    IERC20 internal token1 = IERC20(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47);

    BrewlabsIndexes internal indexes;
    BrewlabsIndexesNft internal nft;
    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    event TokenZappedIn(address indexed user, uint256 ethAmount, uint256[2] percents, uint256[2] amountOuts);
    event TokenZappedOut(address indexed user, uint256 ethAmount, uint256[2] amountOuts);
    event TokenClaimed(address indexed user, uint256[2] amounts);
    event TokenLocked(address indexed user, uint256[2] amounts, uint256 ethAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[2] amounts, uint256 ethAmount, uint256 tokenId);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetFee(uint256 fee);
    event SetSettings(address router, address[][2] paths);

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

        indexes.initialize([token0, token1], IERC721(nft), _router, _paths);
        nft.setMinterRole(address(indexes), true);
    }

    function test_buyTokens() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 amount = 0.5 ether;
        vm.expectEmit(true, false, false, false);
        emit TokenZappedIn(user, 0, [uint256(0), 0], [uint256(0), 0]);
        indexes.buyTokens{value: amount}([uint256(5000), 5000]);

        amount = amount - indexes.performanceFee();
        (uint256[] memory amounts, uint256 zappedEthAmount) = indexes.userInfo(user);
        assertEq(zappedEthAmount, amount - amount * indexes.fee() / 10000);
        assertEq(token0.balanceOf(address(indexes)), amounts[0]);
        assertEq(token1.balanceOf(address(indexes)), amounts[1]);

        assertEq(indexes.totalStaked(0), amounts[0]);
        assertEq(indexes.totalStaked(1), amounts[1]);

        emit log_named_uint("zapped ETH", zappedEthAmount);
        emit log_named_uint("token0", amounts[0]);
        emit log_named_uint("token1", amounts[1]);

        vm.stopPrank();
    }

    function test_claimTokens() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 amount = 0.5 ether;
        indexes.buyTokens{value: amount}([uint256(5000), 5000]);
        (uint256[] memory amounts, uint256 zappedEthAmount) = indexes.userInfo(user);

        uint256 prevBalanceForToken0 = token0.balanceOf(user);
        uint256 prevBalanceForToken1 = token1.balanceOf(user);

        utils.mineBlocks(10);
        vm.expectEmit(true, true, false, true);
        emit TokenClaimed(user, [amounts[0], amounts[1]]);
        indexes.claimTokens{value: indexes.performanceFee()}();

        assertEq(amounts[0], token0.balanceOf(user) - prevBalanceForToken0);
        assertEq(amounts[1], token1.balanceOf(user) - prevBalanceForToken1);

        assertEq(token0.balanceOf(address(indexes)), 0);
        assertEq(token1.balanceOf(address(indexes)), 0);

        assertEq(indexes.totalStaked(0), 0);
        assertEq(indexes.totalStaked(1), 0);

        (amounts, zappedEthAmount) = indexes.userInfo(user);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(zappedEthAmount, 0);
        vm.stopPrank();
    }

    function test_saleTokens() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 amount = 0.5 ether;
        indexes.buyTokens{value: amount}([uint256(5000), 5000]);

        (uint256[] memory amounts, uint256 zappedEthAmount) = indexes.userInfo(user);
        emit log_named_uint("zapped ETH", zappedEthAmount);
        emit log_named_uint("token0", amounts[0]);
        emit log_named_uint("token1", amounts[1]);

        utils.mineBlocks(10);
        vm.expectEmit(true, false, false, false);
        emit TokenZappedOut(user, 0, [uint256(0), 0]);
        indexes.saleTokens{value: indexes.performanceFee()}();

        assertEq(token0.balanceOf(address(indexes)), 0);
        assertEq(token1.balanceOf(address(indexes)), 0);

        assertEq(indexes.totalStaked(0), 0);
        assertEq(indexes.totalStaked(1), 0);

        (amounts, zappedEthAmount) = indexes.userInfo(user);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(zappedEthAmount, 0);
        vm.stopPrank();
    }

    function test_lockTokens() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 amount = 0.5 ether;
        indexes.buyTokens{value: amount}([uint256(5000), 5000]);
        (uint256[] memory amounts, uint256 zappedEthAmount) = indexes.userInfo(user);

        utils.mineBlocks(10);
        vm.expectEmit(true, false, false, false);
        emit TokenLocked(user, [uint256(0), 0], 0, 0);
        uint256 tokenId = indexes.lockTokens{value: indexes.performanceFee()}();
        assertEq(nft.ownerOf(tokenId), user);

        (uint256[] memory _amounts, uint256 _ethAmount) = indexes.nftInfo(tokenId);
        assertEq(_amounts[0], amounts[0]);
        assertEq(_amounts[1], amounts[1]);
        assertEq(_ethAmount, zappedEthAmount);

        assertEq(indexes.totalStaked(0), amounts[0]);
        assertEq(indexes.totalStaked(1), amounts[1]);

        (amounts, zappedEthAmount) = indexes.userInfo(user);
        assertEq(amounts[0], 0);
        assertEq(amounts[1], 0);
        assertEq(zappedEthAmount, 0);
        vm.stopPrank();
    }

    function test_unlockTokens() public {
        address user = address(0x1234);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 amount = 0.5 ether;
        indexes.buyTokens{value: amount}([uint256(5000), 5000]);

        utils.mineBlocks(10);
        uint256 tokenId = indexes.lockTokens{value: indexes.performanceFee()}();

        utils.mineBlocks(10);
        (uint256[] memory _amounts, uint256 _ethAmount) = indexes.nftInfo(tokenId);

        nft.setApprovalForAll(address(indexes), true);

        vm.expectEmit(true, false, false, true);
        emit TokenUnLocked(user, [_amounts[0], _amounts[1]], _ethAmount, tokenId);
        indexes.unlockTokens{value: indexes.performanceFee()}(tokenId);

        assertEq(indexes.totalStaked(0), _amounts[0]);
        assertEq(indexes.totalStaked(1), _amounts[1]);

        (uint256[] memory amounts, uint256 zappedEthAmount) = indexes.userInfo(user);
        assertEq(amounts[0], _amounts[0]);
        assertEq(amounts[1], _amounts[1]);
        assertEq(zappedEthAmount, _ethAmount);
        vm.stopPrank();
    }
}
