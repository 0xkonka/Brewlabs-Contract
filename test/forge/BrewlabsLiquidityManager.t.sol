// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import "forge-std/Test.sol";

import {BrewlabsLiquidityManager, IUniRouter02, IWETH} from "../../contracts/BrewlabsLiquidityManager.sol";

import {MockErc20} from "../../contracts/mocks/MockErc20.sol";

contract BrewlabsLiquidityManagerTest is Test {
    BrewlabsLiquidityManager internal lpManager;
    MockErc20 internal token0;
    MockErc20 internal token1;

    address internal swapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address internal swapRouter1 = 0xcF0feBd3f17CEf5b47b0cD257aCf6025c5BFf3b7;

    uint256 alicePrivateKey = 0xA11CE;
    uint256 bobPrivateKey = 0xB0B;
    address alice = vm.addr(alicePrivateKey);
    address bob = vm.addr(bobPrivateKey);

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    function setUp() public {      
        mainnetFork = vm.createSelectFork(MAINNET_RPC_URL);
        lpManager = new BrewlabsLiquidityManager();

        token0 = new MockErc20(18);
        token1 = new MockErc20(18);
    }

    function test_addLiquidity() public {
        vm.deal(alice, 10 ether);
        token0.mint(alice, 10 ether);
        token1.mint(alice, 10 ether);

        vm.startPrank(alice);
        token0.approve(address(lpManager), 10 ether);
        token1.approve(address(lpManager), 10 ether);

        lpManager.addLiquidity(swapRouter, address(token0), address(token1), 10 ether, 10 ether, 2000);

        assertEq(token0.balanceOf(lpManager.walletA()), 10 ether - 10 ether * 9900 / 10000);
        assertEq(token1.balanceOf(lpManager.walletA()), 10 ether - 10 ether * 9900 / 10000);

        vm.stopPrank();
    }

    function test_addLiquidityETH() public {
        vm.deal(alice, 11 ether);
        token0.mint(alice, 10 ether);
        token1.mint(alice, 10 ether);

        vm.startPrank(alice);
        token0.approve(address(lpManager), 10 ether);

        lpManager.addLiquidityETH{value: 5 ether}(swapRouter, address(token0), 5 ether, 2000);
        assertEq(token0.balanceOf(lpManager.walletA()), 5 ether - 5 ether * 9900 / 10000);

        lpManager.addLiquidityETH{value: 5 ether}(swapRouter1, address(token0), 5 ether, 2000);
        assertEq(token0.balanceOf(lpManager.walletA()), (5 ether - 5 ether * 9900 / 10000) * 2);

        vm.stopPrank();
    }

    function test_removeLiquidity() public {
        vm.deal(alice, 10 ether);
        token0.mint(alice, 10 ether);
        token1.mint(alice, 10 ether);

        vm.startPrank(alice);
        token0.approve(address(lpManager), 10 ether);
        token1.approve(address(lpManager), 10 ether);

        lpManager.addLiquidity(swapRouter, address(token0), address(token1), 10 ether, 10 ether, 2000);

        address pair = lpManager.getPair(swapRouter, address(token0), address(token1));
        uint256 lpBalance = MockErc20(pair).balanceOf(alice);

        MockErc20(pair).approve(address(lpManager), lpBalance);
        lpManager.removeLiquidity(swapRouter, address(token0), address(token1), lpBalance);
        emit log_uint(token0.balanceOf(alice));
        emit log_uint(token1.balanceOf(alice));

        vm.stopPrank();
    }

    function test_removeLiquidityETH() public {
        vm.deal(alice, 11 ether);
        token0.mint(alice, 10 ether);
        token1.mint(alice, 10 ether);

        vm.startPrank(alice);
        token0.approve(address(lpManager), 10 ether);

        lpManager.addLiquidityETH{value: 5 ether}(swapRouter, address(token0), 5 ether, 2000);
        
        address wbnb = IUniRouter02(swapRouter).WETH();
        address pair = lpManager.getPair(swapRouter, address(token0), wbnb);
        uint256 lpBalance = MockErc20(pair).balanceOf(alice);
        

        MockErc20(pair).approve(address(lpManager), lpBalance);
        lpManager.removeLiquidityETH(swapRouter, address(token0), lpBalance);
        // emit log_uint(token0.balanceOf(alice));

        vm.stopPrank();
    }

    
    function test_removeLiquidityETHSupportingFeeOnTransferTokens() public {
        vm.deal(alice, 11 ether);
        token0.mint(alice, 10 ether);
        token1.mint(alice, 10 ether);

        vm.startPrank(alice);
        token0.approve(address(lpManager), 10 ether);

        lpManager.addLiquidityETH{value: 5 ether}(swapRouter1, address(token0), 5 ether, 2000);
        
        address wbnb = IUniRouter02(swapRouter1).WETH();
        address pair = lpManager.getPair(swapRouter1, address(token0), wbnb);
        uint256 lpBalance = MockErc20(pair).balanceOf(alice);
        

        MockErc20(pair).approve(address(lpManager), lpBalance);
        lpManager.removeLiquidityETHSupportingFeeOnTransferTokens(swapRouter1, address(token0), lpBalance);
        // emit log_uint(token0.balanceOf(alice));

        vm.stopPrank();
    }
}
