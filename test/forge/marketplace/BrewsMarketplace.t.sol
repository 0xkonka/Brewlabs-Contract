// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewsMarketplace} from "../../../contracts/marketplace/BrewsMarketplace.sol";
import {MockErc20} from "../../../contracts/mocks/MockErc20.sol";
import {MockErc721} from "../../../contracts/mocks/MockErc721.sol";
import {MockErc1155} from "../../../contracts/mocks/MockErc1155.sol";

import {Utils} from "../utils/Utils.sol";

contract BrewsMarketplaceTest is Test {
    address internal BREWLABS = 0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7;
    address internal USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address internal USDT = 0x55d398326f99059fF775485246999027B3197955;
    address internal DAI = 0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3;

    address internal vendor = address(0x111);
    address internal buyer1 = address(0x333);
    address internal buyer2 = address(0x444);
    address internal deployer = address(0x123);

    BrewsMarketplace internal marketplace;
    MockErc20 internal sellToken;
    MockErc20 internal paidToken1;
    MockErc20 internal paidToken2;
    MockErc1155 internal sellERC1155;
    MockErc721 internal sellERC721;

    Utils internal utils;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = "https://bsc-dataseed.binance.org/";

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        utils = new Utils();

        vm.startPrank(deployer);
        marketplace = new BrewsMarketplace();
        marketplace.initialize();

        sellToken = new MockErc20(18);
        paidToken1 = new MockErc20(18);
        paidToken2 = new MockErc20(6);
        sellERC1155 = new MockErc1155();
        sellERC721 = new MockErc721();

        sellToken.mint(vendor, 100 * 1e18);
        paidToken1.mint(buyer1, 100 * 1e18);
        paidToken2.mint(buyer2, 100 * 1e6);
        sellERC1155.mint(vendor, 10);
        sellERC1155.mint(vendor, 10000);
        sellERC721.mint(vendor);
        address[] memory sellTokens = new address[](3);
        sellTokens[0] = address(sellToken);
        sellTokens[1] = address(sellERC721);
        sellTokens[2] = address(sellERC1155);
        marketplace.enableSellTokens(sellTokens, true);
        address[] memory paidTokens = new address[](2);
        paidTokens[0] = address(paidToken1);
        paidTokens[1] = address(paidToken2);
        marketplace.enablePaidTokens(paidTokens, true);
        vm.stopPrank();
    }

    function tryList(
        address token,
        address paidToken,
        uint256 amount,
        uint256 price
    ) internal {
        marketplace.listToken{value: 0.0035 ether}(
            token,
            2,
            price,
            amount,
            paidToken,
            BrewsMarketplace.AssetType.ERC20,
            0
        );
    }

    function test_standard_listing() public {
        vm.deal(vendor, 1 ether);
        vm.startPrank(vendor);
        sellToken.approve(address(marketplace), 10 * 1e18);
        tryList(address(sellToken), address(paidToken1), 10 * 1e18, 2 * 1e18);
        assertEq(sellToken.balanceOf(address(marketplace)), 10 * 1e18);
        vm.stopPrank();
        vm.startPrank(buyer1);
        vm.deal(buyer1, 1 ether);
        paidToken1.approve(address(marketplace), 20 * 1e18);
        marketplace.purchase{value: 0.0035 ether}(1, 10 * 1e18);
        assertEq(
            paidToken1.balanceOf(address(marketplace)),
            (10 * 2 * 1e18 * (1000 - 3)) / 1000
        );
        skip(12 hours);
        marketplace.claimPurchase{value: 0.0035 ether}(1, 1);
        assertEq(sellToken.balanceOf(address(marketplace)), (75 * 1e17));
        // Claim stable coin for vendor
        vm.stopPrank();
        vm.startPrank(vendor);
        marketplace.claimPaidToken{value: 0.0035 ether}(1, 1);
        vm.stopPrank();

        vm.startPrank(buyer1);
        skip(12 hours);
        marketplace.claimPurchase{value: 0.0035 ether}(1, 1);
        assertEq(sellToken.balanceOf(address(marketplace)), (5 * 1e18));
    }

    function test_constant_vesting() public {
        vm.deal(vendor, 1 ether);
        vm.startPrank(vendor);
        sellToken.approve(address(marketplace), 10 * 1e18);
        marketplace.listToken{value: 0.0035 ether}(
            address(sellToken),
            0,
            2 * 1e18,
            10 * 1e18,
            address(paidToken1),
            BrewsMarketplace.AssetType.ERC20,
            0
        );
        assertEq(sellToken.balanceOf(address(marketplace)), 10 * 1e18);
        vm.stopPrank();

        vm.deal(buyer1, 1 ether);
        vm.startPrank(buyer1);
        paidToken1.approve(address(marketplace), 20 * 1e18);
        marketplace.purchase{value: 0.0035 ether}(1, 2 * 1e18);
        assertEq(
            paidToken1.balanceOf(vendor),
            (2 * 2 * 1e18 * (1000 - 3)) / 1000
        );
        assertEq(sellToken.balanceOf(buyer1), 2 * 1e18);
        BrewsMarketplace.MarketInfo memory m = marketplace.getMarket(1);
        assertEq(m.reserve, 8 * 1e18);
    }

    function test_erc721() public {
        vm.deal(vendor, 1 ether);
        vm.startPrank(vendor);
        sellERC721.setApprovalForAll(address(marketplace), true);
        marketplace.listToken{value: 0.0035 ether}(
            address(sellERC721),
            2,
            2 * 1e18,
            10 * 1e18,
            address(paidToken1),
            BrewsMarketplace.AssetType.ERC721,
            1
        );
        assertEq(sellERC721.ownerOf(1), address(marketplace));
        BrewsMarketplace.MarketInfo memory m = marketplace.getMarket(1);
        assertEq(m.sellAmount, 1);
        vm.stopPrank();

        vm.startPrank(buyer1);
        vm.deal(buyer1, 1 ether);
        paidToken1.approve(address(marketplace), 20 * 1e18);
        marketplace.purchase{value: 0.0035 ether}(1, 1);
        assertEq(
            paidToken1.balanceOf(address(marketplace)),
            (1 * 2 * 1e18 * (1000 - 3)) / 1000
        );
        skip(12 hours);
        vm.expectRevert(bytes("can't claim"));
        marketplace.claimPurchase{value: 0.0035 ether}(1, 1);
        skip(36 hours);
        marketplace.claimPurchase{value: 0.0035 ether}(1, 1);
        assertEq(sellERC721.ownerOf(1), buyer1);
        vm.stopPrank();
        vm.startPrank(vendor);
        assertEq(paidToken1.balanceOf(vendor), 0);
        marketplace.claimPaidToken{value: 0.0035 ether}(1, 1);
        assertEq(paidToken1.balanceOf(vendor), (2 * 1e18 * (1000 - 3)) / 1000);
        (
            BrewsMarketplace.Purchase memory p,
            uint256 claimable,
            uint256 claimedPaidToken
        ) = marketplace.getPurchase(1, 1);
        m = marketplace.getMarket(1);
        assertEq(claimable, 0);
        assertEq(claimedPaidToken, 0);
        assertEq(p.claimed, 1);
        assertEq(m.reserve, 0);
        vm.stopPrank();
    }

    function test_erc1155() public {
        vm.deal(vendor, 1 ether);
        vm.startPrank(vendor);
        sellERC1155.setApprovalForAll(address(marketplace), true);

        marketplace.listToken{value: 0.0035 ether}(
            address(sellERC1155),
            2,
            2 * 1e18,
            5,
            address(paidToken1),
            BrewsMarketplace.AssetType.ERC1155,
            1
        );
        assertEq(sellERC1155.balanceOf(address(marketplace), 1), 5);
        BrewsMarketplace.MarketInfo memory m = marketplace.getMarket(1);
        assertEq(m.sellAmount, 5);
        vm.stopPrank();

        vm.startPrank(buyer1);
        vm.deal(buyer1, 1 ether);
        paidToken1.approve(address(marketplace), 20 * 1e18);
        skip(2 days);
        marketplace.purchase{value: 0.0035 ether}(1, 3);
        assertEq(
            paidToken1.balanceOf(address(marketplace)),
            (3 * 2 * 1e18 * (1000 - 3)) / 1000
        );
        skip(12 hours);
        vm.expectRevert(bytes("can't claim"));
        marketplace.claimPurchase{value: 0.0035 ether}(1, 1);
        skip(12 hours);
        marketplace.claimPurchase{value: 0.0035 ether}(1, 1);
        assertEq(sellERC1155.balanceOf(buyer1, 1), 1);
        vm.stopPrank();
        vm.startPrank(vendor);
        assertEq(paidToken1.balanceOf(vendor), 0);
        marketplace.claimPaidToken{value: 0.0035 ether}(1, 1);
        assertEq(
            paidToken1.balanceOf(vendor),
            (3 * 2 * 1e18 * (1000 - 3)) / 1000 / 2
        );
        skip(1 days);
        (
            BrewsMarketplace.Purchase memory p,
            uint256 claimable,
            uint256 claimedPaidToken
        ) = marketplace.getPurchase(1, 1);
        m = marketplace.getMarket(1);
        assertEq(claimable, 2);
        assertEq(claimedPaidToken, (3 * 2 * 1e18 * (1000 - 3)) / 1000 / 2);
        assertEq(p.claimed, 1);
        assertEq(m.reserve, 2);
        vm.stopPrank();
    }

    receive() external payable {}
}
