// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {BrewlabsNftTransfer, IERC1155, IERC721} from "../../contracts/BrewlabsNftTransfer.sol";
import {MockErc721} from "../../contracts/mocks/MockErc721.sol";
import {MockErc1155} from "../../contracts/mocks/MockErc1155.sol";

contract BrewlabsNftTransferTest is Test {
    BrewlabsNftTransfer internal nftTransferTool;
    MockErc721 internal erc721;
    MockErc1155 internal erc1155;

    function setUp() public {
        nftTransferTool = new BrewlabsNftTransfer();

        erc721 = new MockErc721();
        erc1155 = new MockErc1155();
    }

    function test_singleTransferForErc721() public {
        address user = address(0x123);
        address receipt = address(0x1234);
        uint256 tokenId = erc721.mint(user);

        vm.startPrank(user);
        erc721.setApprovalForAll(address(nftTransferTool), true);
        nftTransferTool.singleTransfer(address(erc721), receipt, tokenId, 0);

        assertEq(erc721.balanceOf(user), 0);
        assertEq(erc721.balanceOf(receipt), 1);
        assertEq(erc721.ownerOf(tokenId), receipt);

        vm.stopPrank();
    }

    function test_singleTransferForErc1155() public {
        address user = address(0x123);
        address receipt = address(0x1234);
        uint256 tokenId = erc1155.mint(user, 10);

        vm.startPrank(user);
        erc1155.setApprovalForAll(address(nftTransferTool), true);
        vm.expectRevert("BrewlabsNftTransfer: Wrong amount");
        nftTransferTool.singleTransfer(address(erc1155), receipt, tokenId, 0);

        nftTransferTool.singleTransfer(address(erc1155), receipt, tokenId, 7);
        assertEq(erc1155.balanceOf(user, tokenId), 3);
        assertEq(erc1155.balanceOf(receipt, tokenId), 7);

        vm.stopPrank();
    }

    function test_bulkTransferOfSingleNftToSameWalletForErc721() public {
        address user = address(0x123);
        address receipt = address(0x1234);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = erc721.mint(user);
            tokenIds[i] = tokenId;
        }

        vm.startPrank(user);
        vm.expectRevert("BrewlabsNftTransfer: Empty transfer");
        nftTransferTool.bulkTransferOfSingleNftToSameWallet{value: pFee}(address(erc721), receipt, amounts, amounts);

        erc721.setApprovalForAll(address(nftTransferTool), true);
        nftTransferTool.bulkTransferOfSingleNftToSameWallet{value: pFee}(address(erc721), receipt, tokenIds, amounts);

        assertEq(erc721.balanceOf(user), 1);
        assertEq(erc721.balanceOf(receipt), 40);
        assertEq(erc721.ownerOf(40), receipt);

        vm.stopPrank();
    }

    function test_bulkTransferOfSingleNftToSameWalletForErc1155() public {
        address user = address(0x123);
        address receipt = address(0x1234);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts = new uint256[](41);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = erc1155.mint(user, 10);
            tokenIds[i] = tokenId;
            amounts[i] = 9;
        }
        uint256[] memory _amounts;

        vm.startPrank(user);
        erc1155.setApprovalForAll(address(nftTransferTool), true);
        vm.expectRevert("BrewlabsNftTransfer: Invaild arguments");
        nftTransferTool.bulkTransferOfSingleNftToSameWallet{value: pFee}(address(erc1155), receipt, tokenIds, _amounts);

        nftTransferTool.bulkTransferOfSingleNftToSameWallet{value: pFee}(address(erc1155), receipt, tokenIds, amounts);
        assertEq(erc1155.balanceOf(user, 3), 1);
        assertEq(erc1155.balanceOf(receipt, 8), 9);

        vm.stopPrank();
    }

    function test_bulkTransferOfSingleNftToDifferentWalletsForErc721() public {
        address user = address(0x123);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        address[] memory receipts = new address[](41);
        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            receipts[i] = address(uint160(1234 + i));
            uint256 tokenId = erc721.mint(user);
            tokenIds[i] = tokenId;
        }
        address[] memory _receipts;

        vm.startPrank(user);
        vm.expectRevert("BrewlabsNftTransfer: no receipt");
        nftTransferTool.bulkTransferOfSingleNftToDifferentWallets{value: pFee}(
            address(erc721), _receipts, tokenIds, amounts
        );

        erc721.setApprovalForAll(address(nftTransferTool), true);
        nftTransferTool.bulkTransferOfSingleNftToDifferentWallets{value: pFee}(
            address(erc721), receipts, tokenIds, amounts
        );

        assertEq(erc721.balanceOf(user), 1);
        assertEq(erc721.balanceOf(receipts[0]), 1);
        assertEq(erc721.ownerOf(40), receipts[39]);

        vm.stopPrank();
    }

    function test_failBulkTransferOfSingleNftToDifferentWallets() public {
        address user = address(0x123);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        address[] memory receipts = new address[](40);
        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (i < 40) receipts[i] = address(uint160(1234 + i));
            uint256 tokenId = erc721.mint(user);
            tokenIds[i] = tokenId;
        }

        vm.startPrank(user);
        vm.expectRevert("BrewlabsNftTransfer: Mismatch arguments for receipt and tokenId");
        nftTransferTool.bulkTransferOfSingleNftToDifferentWallets{value: pFee}(
            address(erc721), receipts, tokenIds, amounts
        );

        vm.stopPrank();
    }

    function test_bulkTransferOfSingleNftToDifferentWalletsForErc1155() public {
        address user = address(0x123);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        address[] memory receipts = new address[](41);
        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts = new uint256[](41);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            receipts[i] = address(uint160(1234 + i));

            uint256 tokenId = erc1155.mint(user, 10);
            tokenIds[i] = tokenId;
            amounts[i] = 9;
        }
        uint256[] memory _amounts;

        vm.startPrank(user);
        erc1155.setApprovalForAll(address(nftTransferTool), true);
        vm.expectRevert("BrewlabsNftTransfer: Invaild arguments");
        nftTransferTool.bulkTransferOfSingleNftToDifferentWallets{value: pFee}(
            address(erc1155), receipts, tokenIds, _amounts
        );

        nftTransferTool.bulkTransferOfSingleNftToDifferentWallets{value: pFee}(
            address(erc1155), receipts, tokenIds, amounts
        );
        assertEq(erc1155.balanceOf(user, 3), 1);
        assertEq(erc1155.balanceOf(receipts[7], 8), 9);

        vm.stopPrank();
    }

    function test_bulkTransferOfMultipleNftsToSameWallet() public {
        address user = address(0x123);
        address receipt = address(0x1234);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        address[] memory nfts = new address[](41);
        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts = new uint256[](41);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (i % 2 == 0) {
                MockErc721 nft = new MockErc721();
                uint256 tokenId = nft.mint(user);
                nfts[i] = address(nft);
                tokenIds[i] = tokenId;
            } else {
                MockErc1155 nft = new MockErc1155();
                uint256 tokenId = nft.mint(user, 10);

                nfts[i] = address(nft);
                tokenIds[i] = tokenId;
                amounts[i] = 9;
            }
        }
        address[] memory _nfts;

        vm.startPrank(user);
        for (uint256 i = 0; i < 41; i++) {
            IERC721(nfts[i]).setApprovalForAll(address(nftTransferTool), true);
        }
        vm.expectRevert("BrewlabsNftTransfer: NFT not selected");
        nftTransferTool.bulkTransferOfMultipleNftsToSameWallet{value: pFee}(_nfts, receipt, tokenIds, amounts);

        nftTransferTool.bulkTransferOfMultipleNftsToSameWallet{value: pFee}(nfts, receipt, tokenIds, amounts);
        assertEq(IERC1155(nfts[7]).balanceOf(user, 1), 1);
        assertEq(IERC1155(nfts[7]).balanceOf(receipt, 1), 9);
        assertEq(IERC721(nfts[8]).balanceOf(receipt), 1);
        assertEq(IERC721(nfts[8]).ownerOf(1), receipt);

        vm.stopPrank();
    }

    function test_bulkTransferOfMultipleNftsToDifferentWallets() public {
        address user = address(0x123);
        vm.deal(user, 1 ether);

        uint256 pFee = nftTransferTool.performanceFee();

        address[] memory nfts = new address[](41);
        address[] memory receipts = new address[](41);
        uint256[] memory tokenIds = new uint256[](41);
        uint256[] memory amounts = new uint256[](41);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            receipts[i] = address(uint160(1234 + i));

            if (i % 2 == 0) {
                MockErc721 nft = new MockErc721();
                uint256 tokenId = nft.mint(user);

                nfts[i] = address(nft);
                tokenIds[i] = tokenId;
            } else {
                MockErc1155 nft = new MockErc1155();
                uint256 tokenId = nft.mint(user, 10);

                nfts[i] = address(nft);
                tokenIds[i] = tokenId;
                amounts[i] = 9;
            }
        }
        address[] memory _nfts;

        vm.startPrank(user);
        for (uint256 i = 0; i < 41; i++) {
            IERC721(nfts[i]).setApprovalForAll(address(nftTransferTool), true);
        }

        vm.expectRevert("BrewlabsNftTransfer: NFT not selected");
        nftTransferTool.bulkTransferOfMultipleNftsToDifferentWallets{value: pFee}(_nfts, receipts, tokenIds, amounts);

        nftTransferTool.bulkTransferOfMultipleNftsToDifferentWallets{value: pFee}(nfts, receipts, tokenIds, amounts);
        assertEq(IERC1155(nfts[7]).balanceOf(user, 1), 1);
        assertEq(IERC1155(nfts[7]).balanceOf(receipts[7], 1), 9);
        assertEq(IERC721(nfts[8]).balanceOf(receipts[8]), 1);
        assertEq(IERC721(nfts[8]).ownerOf(1), receipts[8]);

        vm.stopPrank();
    }

    receive() external payable {}
}
