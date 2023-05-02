// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {BrewlabsIndex, IBrewlabsIndexNft, IERC20} from "../../../contracts/indexes/BrewlabsIndex.sol";
import {BrewlabsIndexFactory} from "../../../contracts/indexes/BrewlabsIndexFactory.sol";
import {BrewlabsIndexNft, IERC721} from "../../../contracts/indexes/BrewlabsIndexNft.sol";
import {BrewlabsNftDiscountMgr} from "../../../contracts/BrewlabsNftDiscountMgr.sol";
import {BrewlabsDeployerNft} from "../../../contracts/indexes/BrewlabsDeployerNft.sol";
import {IBrewlabsIndex} from "../../../contracts/indexes/IBrewlabsIndex.sol";
import {Utils} from "../utils/Utils.sol";

contract BrewlabsIndexTest is Test {
    IERC20 internal token0 = IERC20(0x2170Ed0880ac9A755fd29B2688956BD959F933F8);
    IERC20 internal token1 = IERC20(0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47);

    address internal indexOwner = address(0x111);
    address internal deployer = address(0x123);

    BrewlabsIndexFactory internal factory;
    BrewlabsIndexNft internal indexNft;
    BrewlabsDeployerNft internal deployerNft;
    BrewlabsNftDiscountMgr internal discountMgr;
    IBrewlabsIndex internal index;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    event TokenZappedIn(
        address indexed user,
        uint256 ethAmount,
        uint256[] percents,
        uint256[] amountOuts,
        uint256 usdAmount,
        uint256 commission
    );
    event TokenZappedOut(address indexed user, uint256[] amounts, uint256 ethAmount, uint256 commission);
    event TokenClaimed(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 commission);
    event TokenLocked(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 tokenId);
    event TokenUnLocked(address indexed user, uint256[] amounts, uint256 usdAmount, uint256 tokenId);

    event DeployerNftMinted(address indexed user, address nft, uint256 tokenId);
    event DeployerNftStaked(address indexed user, uint256 tokenId);
    event DeployerNftUnstaked(address indexed user, uint256 tokenId);
    event PendingCommissionClaimed(address indexed user);

    event ServiceInfoUpadted(address addr, uint256 fee);
    event SetDeployerFee(uint256 fee);
    event SetSettings(address router, address[][] paths);

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();

        BrewlabsIndex impl = new BrewlabsIndex();
        indexNft = new BrewlabsIndexNft();
        deployerNft = new BrewlabsDeployerNft();
        discountMgr = new BrewlabsNftDiscountMgr();

        factory = new BrewlabsIndexFactory();
        factory.initialize(
            address(impl), indexNft, deployerNft, 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56, 0, indexOwner
        );
        factory.setDiscountManager(address(discountMgr));
        indexNft.setAdmin(address(factory));
        deployerNft.setAdmin(address(factory));

        address _router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        address[][] memory _paths = new address[][](2);
        _paths[0] = new address[](2);
        _paths[1] = new address[](2);
        _paths[0][0] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        _paths[0][1] = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
        _paths[1][0] = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        _paths[1][1] = 0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47;

        vm.startPrank(deployer);
        index = IBrewlabsIndex(factory.createBrewlabsIndex(tokens, _router, _paths, 20)); // 0.2%
        vm.stopPrank();
    }

    function test_zapInWithEth() public {
        address user = address(0x12345);
        vm.deal(user, 10 ether);
        vm.startPrank(user);

        uint256 price = index.getPriceFromChainlink();

        uint256[] memory _amounts;
        uint256[] memory percents = new uint256[](2);
        percents[0] = 5000;
        percents[1] = 5000;
        uint256 amount = 0.5 ether;
        vm.expectEmit(true, false, false, false);
        emit TokenZappedIn(user, 0, percents, _amounts, 0, 0);
        index.zapIn{value: amount}(address(0), 0, percents);

        (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);

        assertEq(usdAmount, (amount - (amount * index.totalFee()) / 10000) * price / 1 ether);
        assertEq(token0.balanceOf(address(index)), amounts[0]);
        assertEq(token1.balanceOf(address(index)), amounts[1]);

        assertEq(index.totalStaked(0), amounts[0]);
        assertEq(index.totalStaked(1), amounts[1]);

        emit log_named_uint("USD Amount", usdAmount);
        emit log_named_uint("token0", amounts[0]);
        emit log_named_uint("token1", amounts[1]);

        vm.stopPrank();
    }

    // function test_claimTokens() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 10 ether);
    //     vm.startPrank(user);

    //     uint256 amount = 0.5 ether;
    //     uint256[] memory percents = new uint256[](2);
    //     percents[0] = 5000;
    //     percents[1] = 5000;
    //     index.zapIn{value: amount}(percents);
    //     (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);

    //     uint256 estimatedEthAmount = index.estimateEthforUser(user);
    //     uint256 price = index.getPriceFromChainlink();
    //     if (estimatedEthAmount * price / 1 ether > usdAmount) {
    //         amounts[0] -= amounts[0] * index.fee() / 10000;
    //         amounts[1] -= amounts[1] * index.fee() / 10000;
    //     }

    //     uint256 prevBalanceForToken0 = token0.balanceOf(user);
    //     uint256 prevBalanceForToken1 = token1.balanceOf(user);

    //     utils.mineBlocks(10);
    //     vm.expectEmit(true, false, false, false);
    //     emit TokenClaimed(user, amounts, 0, 0);
    //     index.claimTokens(10000);

    //     assertEq(amounts[0], token0.balanceOf(user) - prevBalanceForToken0);
    //     assertEq(amounts[1], token1.balanceOf(user) - prevBalanceForToken1);

    //     assertEq(token0.balanceOf(address(index)), 0);
    //     assertEq(token1.balanceOf(address(index)), 0);

    //     assertEq(index.totalStaked(0), 0);
    //     assertEq(index.totalStaked(1), 0);

    //     (amounts, usdAmount) = index.userInfo(user);
    //     assertEq(amounts[0], 0);
    //     assertEq(amounts[1], 0);
    //     assertEq(usdAmount, 0);
    //     vm.stopPrank();
    // }

    // function test_zapOut() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 10 ether);
    //     vm.startPrank(user);

    //     uint256 amount = 0.5 ether;
    //     uint256[] memory percents = new uint256[](2);
    //     percents[0] = 5000;
    //     percents[1] = 5000;
    //     index.zapIn{value: amount}(percents);

    //     (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);
    //     emit log_named_uint("USD Amount", usdAmount);
    //     emit log_named_uint("token0", amounts[0]);
    //     emit log_named_uint("token1", amounts[1]);

    //     utils.mineBlocks(10);
    //     vm.expectEmit(true, false, false, false);
    //     emit TokenZappedOut(user, amounts, 0, 0);
    //     index.zapOut();

    //     assertEq(token0.balanceOf(address(index)), 0);
    //     assertEq(token1.balanceOf(address(index)), 0);

    //     assertEq(index.totalStaked(0), 0);
    //     assertEq(index.totalStaked(1), 0);

    //     (amounts, usdAmount) = index.userInfo(user);
    //     assertEq(amounts[0], 0);
    //     assertEq(amounts[1], 0);
    //     assertEq(usdAmount, 0);
    //     vm.stopPrank();
    // }

    // function test_mintNft() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 10 ether);
    //     vm.startPrank(user);

    //     uint256 amount = 0.5 ether;
    //     uint256[] memory percents = new uint256[](2);
    //     percents[0] = 5000;
    //     percents[1] = 5000;
    //     index.zapIn{value: amount}(percents);
    //     (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);

    //     utils.mineBlocks(10);
    //     vm.expectEmit(true, false, false, false);
    //     emit TokenLocked(user, amounts, 0, 0);
    //     uint256 tokenId = index.mintNft{value: index.performanceFee()}();
    //     assertEq(indexNft.ownerOf(tokenId), user);

    //     string memory _tokenUri = indexNft.tokenURI(tokenId);
    //     emit log_named_string("URI: ", _tokenUri);

    //     (, uint256[] memory _amounts, uint256 _ethAmount) = index.nftInfo(tokenId);
    //     assertEq(_amounts[0], amounts[0]);
    //     assertEq(_amounts[1], amounts[1]);
    //     assertEq(_ethAmount, usdAmount);

    //     assertEq(index.totalStaked(0), amounts[0]);
    //     assertEq(index.totalStaked(1), amounts[1]);

    //     (amounts, usdAmount) = index.userInfo(user);
    //     assertEq(amounts[0], 0);
    //     assertEq(amounts[1], 0);
    //     assertEq(usdAmount, 0);
    //     vm.stopPrank();
    // }

    // function test_stakeNft() public {
    //     address user = address(0x1234);
    //     vm.deal(user, 10 ether);
    //     vm.startPrank(user);

    //     uint256 amount = 0.5 ether;
    //     uint256[] memory percents = new uint256[](2);
    //     percents[0] = 5000;
    //     percents[1] = 5000;
    //     index.zapIn{value: amount}(percents);

    //     utils.mineBlocks(10);
    //     uint256 tokenId = index.mintNft{value: index.performanceFee()}();

    //     utils.mineBlocks(10);
    //     (, uint256[] memory _amounts, uint256 _ethAmount) = index.nftInfo(tokenId);

    //     indexNft.setApprovalForAll(address(index), true);

    //     vm.expectEmit(true, false, false, true);
    //     emit TokenUnLocked(user, _amounts, _ethAmount, tokenId);
    //     index.stakeNft{value: index.performanceFee()}(tokenId);

    //     assertEq(index.totalStaked(0), _amounts[0]);
    //     assertEq(index.totalStaked(1), _amounts[1]);

    //     (uint256[] memory amounts, uint256 usdAmount) = index.userInfo(user);
    //     assertEq(amounts[0], _amounts[0]);
    //     assertEq(amounts[1], _amounts[1]);
    //     assertEq(usdAmount, _ethAmount);
    //     vm.stopPrank();
    // }
}
