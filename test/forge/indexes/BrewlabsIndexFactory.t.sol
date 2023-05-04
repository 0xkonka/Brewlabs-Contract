// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsIndex, IERC20} from "../../../contracts/indexes/BrewlabsIndex.sol";
import {BrewlabsIndexFactory} from "../../../contracts/indexes/BrewlabsIndexFactory.sol";
import {BrewlabsIndexNft, IERC721} from "../../../contracts/indexes/BrewlabsIndexNft.sol";
import {BrewlabsNftDiscountMgr} from "../../../contracts/BrewlabsNftDiscountMgr.sol";
import {BrewlabsDeployerNft} from "../../../contracts/indexes/BrewlabsDeployerNft.sol";

import {IBrewlabsIndex} from "../../../contracts/indexes/IBrewlabsIndex.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsIndexFactoryTest is Test {
    IERC20 internal token0 = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    IERC20 internal token1 = IERC20(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47);

    address swapRouter = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
    address internal WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address internal BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address internal USDT = 0x55d398326f99059fF775485246999027B3197955;
    address internal USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    uint256 internal FEE_DENOMINATOR = 10000;

    address internal indexOwner = address(0x111);
    address internal deployer = address(0x123);

    BrewlabsIndexFactory internal factory;
    BrewlabsIndexNft internal indexNft;
    BrewlabsDeployerNft internal deployerNft;
    BrewlabsNftDiscountMgr internal discountMgr;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    event IndexCreated(
        address indexed index,
        address[] tokens,
        address indexNft,
        address deployerNft,
        address swapRouter,
        address deployer
    );
    event SetIndexNft(address newNftAddr);
    event SetDeployerNft(address newOwner);
    event SetIndexOwner(address newOwner);
    event SetBrewlabsFee(uint256 fee);
    event SetBrewlabsWallet(address wallet);
    event SetIndexFeeLimit(uint256 limit);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(address impl, uint256 version);
    event SetDiscountMgr(address addr);
    event TreasuryChanged(address addr);

    event SetTokenConfig(address token, uint8 flag);
    event Whitelisted(address indexed account, bool isWhitelisted);

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();

        indexNft = new BrewlabsIndexNft();
        deployerNft = new BrewlabsDeployerNft();
        discountMgr = new BrewlabsNftDiscountMgr();

        factory = new BrewlabsIndexFactory();
    }

    function test_initialize() public {
        indexNft.setAdmin(address(factory));
        deployerNft.setAdmin(address(factory));

        BrewlabsIndex impl = new BrewlabsIndex();

        vm.expectEmit(false, false, false, true);
        emit SetImplementation(address(impl), 1);
        factory.initialize(address(impl), indexNft, deployerNft, BUSD, 1 ether, indexOwner);

        assertEq(factory.implementation(), address(impl));
        assertEq(factory.version(), 1);
        assertEq(factory.indexCount(), 0);
    }

    function test_failInitializeWithZeroImpl() public {
        vm.expectRevert("Invalid implementation");
        factory.initialize(address(0), indexNft, deployerNft, BUSD, 1 ether, indexOwner);
    }

    function test_failInitializeWithNoIndexNft() public {
        BrewlabsIndex impl = new BrewlabsIndex();
        vm.expectRevert("Invalid index NFT");
        factory.initialize(address(impl), IERC721(address(0)), deployerNft, BUSD, 1 ether, indexOwner);
    }

    function test_failInitializeWithNoDeployerNft() public {
        BrewlabsIndex impl = new BrewlabsIndex();
        vm.expectRevert("Invalid deployer NFT");
        factory.initialize(address(impl), indexNft, IERC721(address(0)), BUSD, 1 ether, indexOwner);
    }

    function tryInitialize() internal {
        indexNft.setAdmin(address(factory));
        deployerNft.setAdmin(address(factory));

        BrewlabsIndex impl = new BrewlabsIndex();
        factory.initialize(address(impl), indexNft, deployerNft, BUSD, 1 ether, indexOwner);
    }

    function test_setImplementation() public {
        tryInitialize();

        vm.expectRevert("Invalid implementation");
        factory.setImplementation(address(0));

        BrewlabsIndex impl = new BrewlabsIndex();
        vm.expectEmit(false, false, false, true);
        emit SetImplementation(address(impl), 2);
        factory.setImplementation(address(impl));

        assertEq(factory.implementation(), address(impl));
        assertEq(factory.version(), 2);
    }

    function test_setIndexNft() public {
        tryInitialize();

        vm.expectRevert("Invalid NFT");
        factory.setIndexNft(IERC721(address(0)));

        BrewlabsIndexNft _nft = new BrewlabsIndexNft();

        vm.expectEmit(false, false, false, true);
        emit SetIndexNft(address(_nft));
        factory.setIndexNft(_nft);
    }

    function test_setDeployerNft() public {
        tryInitialize();

        vm.expectRevert("Invalid NFT");
        factory.setDeployerNft(IERC721(address(0)));

        BrewlabsDeployerNft _nft = new BrewlabsDeployerNft();

        vm.expectEmit(false, false, false, true);
        emit SetDeployerNft(address(_nft));
        factory.setDeployerNft(_nft);
    }

    function test_createBrewlabsIndexInETHfee() public {
        tryInitialize();
        factory.setPayingToken(address(0));

        vm.deal(deployer, 10 ether);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = address(token0);
        _paths[1][0] = WBNB;
        _paths[1][1] = address(token1);

        vm.startPrank(deployer);
        vm.expectRevert("Not enough fee");
        factory.createBrewlabsIndex(tokens, swapRouter, _paths, 200);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(token0);
        _tokens[1] = address(token1);

        vm.expectEmit(false, false, false, true);
        emit IndexCreated(address(0), _tokens, address(indexNft), address(deployerNft), swapRouter, deployer);
        address index = factory.createBrewlabsIndex{value: 1 ether}(tokens, swapRouter, _paths, 200);

        assertEq(IBrewlabsIndex(index).deployer(), deployer);
        assertEq(IBrewlabsIndex(index).owner(), indexOwner);

        assertEq(IBrewlabsIndex(index).NUM_TOKENS(), 2);
        assertEq(IBrewlabsIndex(index).totalFee(), 200 + factory.brewlabsFee());
        vm.stopPrank();
    }

    function test_createBrewlabsIndexInTokenfee() public {
        tryInitialize();
        MockErc20 payingToken = new MockErc20(18);
        factory.setPayingToken(address(payingToken));

        vm.deal(deployer, 10 ether);
        payingToken.mint(deployer, 1 ether);

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = address(token0);
        _paths[1][0] = WBNB;
        _paths[1][1] = address(token1);

        vm.startPrank(deployer);
        payingToken.approve(address(factory), 1 ether);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(token0);
        _tokens[1] = address(token1);

        vm.expectEmit(false, false, false, true);
        emit IndexCreated(address(0), _tokens, address(indexNft), address(deployerNft), swapRouter, deployer);
        factory.createBrewlabsIndex(tokens, swapRouter, _paths, 200);
    }

    receive() external payable {}
}
