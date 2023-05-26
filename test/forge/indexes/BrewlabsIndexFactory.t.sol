// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsIndex, IERC20} from "../../../contracts/indexes/BrewlabsIndex.sol";
import {BrewlabsIndexFactory} from "../../../contracts/indexes/BrewlabsIndexFactory.sol";
import {BrewlabsIndexNft, IERC721} from "../../../contracts/indexes/BrewlabsIndexNft.sol";
import {BrewlabsNftDiscountMgr} from "../../../contracts/indexes/BrewlabsNftDiscountMgr.sol";
import {BrewlabsDeployerNft} from "../../../contracts/indexes/BrewlabsDeployerNft.sol";

import {IBrewlabsIndex} from "../../../contracts/indexes/IBrewlabsIndex.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewlabsIndexFactoryTest is Test {
    address internal token0 = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    address internal token1 = 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47;

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
        uint256 category,
        uint256 version,
        address[] tokens,
        address indexNft,
        address deployerNft,
        address deployer
    );
    event SetIndexNft(address newNftAddr);
    event SetDeployerNft(address newOwner);
    event SetIndexOwner(address newOwner);
    event SetBrewlabsFee(uint256 fee);
    event SetBrewlabsWallet(address wallet);
    event SetIndexFeeLimit(uint256 limit);
    event SetPayingInfo(address token, uint256 price);
    event SetImplementation(uint256 category, address impl, uint256 version);
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
        indexNft.setAdmin(address(factory));
        deployerNft.setAdmin(address(factory));

        BrewlabsIndex impl = new BrewlabsIndex();
        factory.initialize(address(impl), indexNft, deployerNft, BUSD, 1 ether, indexOwner);
    }

    function test_initialize() public {
        BrewlabsIndexFactory _factory = new BrewlabsIndexFactory();
        indexNft.setAdmin(address(_factory));
        deployerNft.setAdmin(address(_factory));

        BrewlabsIndex impl = new BrewlabsIndex();

        vm.expectEmit(false, false, false, true);
        emit SetImplementation(0, address(impl), 1);
        _factory.initialize(address(impl), indexNft, deployerNft, BUSD, 1 ether, indexOwner);

        assertEq(_factory.implementation(0), address(impl));
        assertEq(_factory.version(0), 1);
        assertEq(_factory.indexCount(), 0);
    }

    function test_failInitializeWithZeroImpl() public {
        BrewlabsIndexFactory _factory = new BrewlabsIndexFactory();

        vm.expectRevert("Invalid implementation");
        _factory.initialize(address(0), indexNft, deployerNft, BUSD, 1 ether, indexOwner);
    }

    function test_failInitializeWithNoIndexNft() public {
        BrewlabsIndexFactory _factory = new BrewlabsIndexFactory();

        BrewlabsIndex impl = new BrewlabsIndex();
        vm.expectRevert("Invalid index NFT");
        _factory.initialize(address(impl), IERC721(address(0)), deployerNft, BUSD, 1 ether, indexOwner);
    }

    function test_failInitializeWithNoDeployerNft() public {
        BrewlabsIndexFactory _factory = new BrewlabsIndexFactory();

        BrewlabsIndex impl = new BrewlabsIndex();
        vm.expectRevert("Invalid deployer NFT");
        _factory.initialize(address(impl), indexNft, IERC721(address(0)), BUSD, 1 ether, indexOwner);
    }

    function test_setImplementation() public {
        vm.expectRevert("Invalid implementation");
        factory.setImplementation(0, address(0));

        BrewlabsIndex impl = new BrewlabsIndex();
        vm.expectEmit(false, false, false, true);
        emit SetImplementation(0, address(impl), 2);
        factory.setImplementation(0, address(impl));

        assertEq(factory.implementation(0), address(impl));
        assertEq(factory.version(0), 2);
    }

    function test_setIndexNft() public {
        vm.expectRevert("Invalid NFT");
        factory.setIndexNft(IERC721(address(0)));

        BrewlabsIndexNft _nft = new BrewlabsIndexNft();

        vm.expectEmit(false, false, false, true);
        emit SetIndexNft(address(_nft));
        factory.setIndexNft(_nft);
    }

    function test_setDeployerNft() public {
        vm.expectRevert("Invalid NFT");
        factory.setDeployerNft(IERC721(address(0)));

        BrewlabsDeployerNft _nft = new BrewlabsDeployerNft();

        vm.expectEmit(false, false, false, true);
        emit SetDeployerNft(address(_nft));
        factory.setDeployerNft(_nft);
    }

    function test_setBrewlabsWallet() public {
        vm.expectRevert("Invalid wallet");
        factory.setBrewlabsWallet(address(0));

        vm.expectEmit(false, false, false, true);
        emit SetBrewlabsWallet(address(0x1));
        factory.setBrewlabsWallet(address(0x1));
    }

    function test_setIndexOwner() public {
        vm.expectRevert("Invalid address");
        factory.setIndexOwner(address(0));

        vm.expectEmit(false, false, false, true);
        emit SetIndexOwner(address(0x1));
        factory.setIndexOwner(address(0x1));
    }

    function test_setDiscountManager() public {
        vm.expectRevert("Invalid discount manager");
        factory.setDiscountManager(address(0x1));

        vm.expectEmit(false, false, false, true);
        emit SetDiscountMgr(address(discountMgr));
        factory.setDiscountManager(address(discountMgr));
        assertEq(factory.discountMgr(), address(discountMgr));

        factory.setDiscountManager(address(0x0));
        assertEq(factory.discountMgr(), address(0x0));
    }

    function test_setBrewlabsFee() public {
        vm.expectRevert("fee cannot exceed limit");
        factory.setBrewlabsFee(1001);

        vm.expectEmit(false, false, false, true);
        emit SetBrewlabsFee(100);
        factory.setBrewlabsFee(100);

        assertEq(factory.brewlabsFee(), 100);
    }

    function test_setServiceFee() public {
        vm.expectEmit(false, false, false, true);
        emit SetPayingInfo(factory.payingToken(), 1 ether);
        factory.setServiceFee(1 ether);
    }

    function test_setPayingToken() public {
        vm.expectEmit(false, false, false, true);
        emit SetPayingInfo(address(0x1), factory.serviceFee());
        factory.setPayingToken(address(0x1));
    }

    function test_setAllowedToken() public {
        vm.expectRevert("Invalid token");
        factory.setAllowedToken(address(0x0), 1);

        vm.expectEmit(false, false, false, true);
        emit SetTokenConfig(address(0x1), 1);
        factory.setAllowedToken(address(0x1), 1);

        assertEq(factory.allowedTokens(address(0x1)), 1);
    }

    function test_addToWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(address(0x1), true);
        factory.addToWhitelist(address(0x1));

        assertTrue(factory.whitelist(address(0x1)));
    }

    function test_removeFromWhitelist() public {
        vm.expectEmit(true, false, false, true);
        emit Whitelisted(address(0x1), false);
        factory.removeFromWhitelist(address(0x1));

        assertFalse(factory.whitelist(address(0x1)));
    }

    function test_setTreasury() public {
        vm.expectRevert("Invalid address");
        factory.setTreasury(address(0));

        vm.expectEmit(true, false, false, true);
        emit TreasuryChanged(address(0x1));
        factory.setTreasury(address(0x1));
    }

    function test_createBrewlabsIndexInETHfee() public {
        factory.setPayingToken(address(0));

        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        vm.expectRevert("Not enough fee");
        factory.createBrewlabsIndex(tokens, 200);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(token0);
        _tokens[1] = address(token1);

        vm.expectEmit(false, false, false, true);
        emit IndexCreated(address(0), 0, 1, _tokens, address(indexNft), address(deployerNft), deployer);
        address index = factory.createBrewlabsIndex{value: 1 ether}(tokens, 200);

        assertEq(IBrewlabsIndex(index).deployer(), deployer);
        assertEq(IBrewlabsIndex(index).owner(), indexOwner);

        assertEq(IBrewlabsIndex(index).NUM_TOKENS(), 2);
        assertEq(IBrewlabsIndex(index).totalFee(), 200 + factory.brewlabsFee());
        vm.stopPrank();
    }

    function test_createBrewlabsIndexInTokenfee() public {
        MockErc20 payingToken = new MockErc20(18);
        factory.setPayingToken(address(payingToken));

        vm.deal(deployer, 10 ether);
        payingToken.mint(deployer, 1 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        payingToken.approve(address(factory), 1 ether);

        address[] memory _tokens = new address[](2);
        _tokens[0] = address(token0);
        _tokens[1] = address(token1);

        vm.expectEmit(false, false, false, true);
        emit IndexCreated(address(0), 0, 1, _tokens, address(indexNft), address(deployerNft), deployer);
        factory.createBrewlabsIndex(tokens, 200);
    }

    function test_createBrewlabsIndexInNoFee() public {
        factory.setPayingToken(address(0));
        factory.addToWhitelist(deployer);

        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        address[] memory _tokens = new address[](2);
        _tokens[0] = address(token0);
        _tokens[1] = address(token1);

        vm.expectEmit(false, false, false, true);
        emit IndexCreated(address(0), 0, 1, _tokens, address(indexNft), address(deployerNft), deployer);
        address index = factory.createBrewlabsIndex(tokens, 200);

        assertEq(IBrewlabsIndex(index).deployer(), deployer);
        assertEq(IBrewlabsIndex(index).owner(), indexOwner);

        assertEq(IBrewlabsIndex(index).NUM_TOKENS(), 2);
        assertEq(IBrewlabsIndex(index).totalFee(), 200 + factory.brewlabsFee());
        vm.stopPrank();
    }

    function test_failCreateBrewlabsIndexInNoInitialized() public {
        BrewlabsIndexFactory _factory = new BrewlabsIndexFactory();

        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        vm.expectRevert("Not initialized yet");
        _factory.createBrewlabsIndex(tokens, 200);
        vm.stopPrank();
    }

    function test_failCreateBrewlabsIndexInExceedTokenLength() public {
        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](6);
        tokens[0] = token0;
        tokens[1] = token0;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        vm.expectRevert("Exceed token limit");
        factory.createBrewlabsIndex(tokens, 200);
        vm.stopPrank();
    }

    function test_failCreateBrewlabsIndexInExceedFeeLimit() public {
        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        vm.expectRevert("Cannot exeed fee limit");
        factory.createBrewlabsIndex(tokens, 2000);
        vm.stopPrank();
    }

    function test_failCreateBrewlabsIndexInSameTokens() public {
        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token0;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        vm.expectRevert("Cannot use same token");
        factory.createBrewlabsIndex(tokens, 200);
        vm.stopPrank();
    }

    function test_failCreateBrewlabsIndexInValidToken() public {
        vm.deal(deployer, 10 ether);

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = address(0x1);

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = WBNB;
        _paths[0][1] = token0;
        _paths[1][0] = WBNB;
        _paths[1][1] = token1;

        vm.startPrank(deployer);
        vm.expectRevert("Invalid token");
        factory.createBrewlabsIndex(tokens, 200);
        vm.stopPrank();
    }

    function test_rescueTokensForEther() public {
        vm.deal(address(factory), 0.02 ether);
        factory.rescueTokens(address(0x0));
        assertEq(address(factory).balance, 0);
    }

    function test_rescueTokensForErc20() public {
        MockErc20 token = new MockErc20(18);
        token.mint(address(factory), 1000 ether);
        factory.rescueTokens(address(token));
        assertEq(token.balanceOf(address(factory)), 0);
    }

    function test_rescueTokensAsOwner() public {
        address owner = factory.owner();
        uint256 prevBalance = owner.balance;

        vm.deal(address(factory), 0.02 ether);
        factory.rescueTokens(address(0x0));

        assertEq(owner.balance, prevBalance + 0.02 ether);
    }

    function test_rescueTokensFailsAsNotOwner() public {
        vm.startPrank(address(0x1));

        vm.deal(address(factory), 0.02 ether);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.rescueTokens(address(0x0));

        vm.stopPrank();
    }

    receive() external payable {}
}
