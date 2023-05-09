// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC721, IERC165} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

contract BrewlabsNftTransfer is Ownable {
    uint256 public transferLimit = 40;

    address public treasury = 0x5Ac58191F3BBDF6D037C6C6201aDC9F99c93C53A;
    uint256 public performanceFee;

    event ServiceInfoChanged(address addr, uint256 fee);
    event TransferLimitChanged(uint256 limit);

    constructor() {}

    function singleTransfer(address nft, address to, uint256 tokenId, uint256 amount) external {
        if (IERC165(nft).supportsInterface(type(IERC1155).interfaceId)) {
            require(amount > 0, "BrewlabsNftTransfer: Wrong amount");
            IERC1155(nft).safeTransferFrom(msg.sender, to, tokenId, amount, "");
        } else {
            IERC721(nft).safeTransferFrom(msg.sender, to, tokenId);
        }
    }

    function bulkTransferOfSingleNftToSameWallet(
        address nft,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) external payable {
        require(tokenIds.length > 0, "BrewlabsNftTransfer: Empty transfer");

        _transferPerformanceFee();

        if (IERC165(nft).supportsInterface(type(IERC1155).interfaceId)) {
            require(tokenIds.length == amounts.length, "BrewlabsNftTransfer: Invaild arguments");
            IERC1155(nft).safeBatchTransferFrom(msg.sender, to, tokenIds, amounts, "");
        } else {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                if (i >= transferLimit) break;
                IERC721(nft).safeTransferFrom(msg.sender, to, tokenIds[i]);
            }
        }
    }

    function bulkTransferOfSingleNftToDifferentWallets(
        address nft,
        address[] memory to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) external payable {
        require(to.length > 0, "BrewlabsNftTransfer: no receipt");
        require(tokenIds.length == to.length, "Mismatch arguments for receipt and tokenId");

        _transferPerformanceFee();

        if (IERC165(nft).supportsInterface(type(IERC1155).interfaceId)) {
            require(tokenIds.length == amounts.length, "BrewlabsNftTransfer: Invaild arguments");
            for (uint256 i = 0; i < tokenIds.length; i++) {
                if (i >= transferLimit) break;
                IERC1155(nft).safeTransferFrom(msg.sender, to[i], tokenIds[i], amounts[i], "");
            }
        } else {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                if (i >= transferLimit) break;
                IERC721(nft).safeTransferFrom(msg.sender, to[i], tokenIds[i]);
            }
        }
    }

    function bulkTransferOfMultipleNftsToSameWallet(
        address[] memory nfts,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) external payable {
        require(nfts.length > 0, "BrewlabsNftTransfer: NFT not selected");
        require(nfts.length == tokenIds.length && nfts.length == amounts.length, "Invalid arguments");

        _transferPerformanceFee();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (i >= transferLimit) break;
            if (IERC165(nfts[i]).supportsInterface(type(IERC1155).interfaceId)) {
                IERC1155(nfts[i]).safeTransferFrom(msg.sender, to, tokenIds[i], amounts[i], "");
            } else {
                IERC721(nfts[i]).safeTransferFrom(msg.sender, to, tokenIds[i]);
            }
        }
    }

    function bulkTransferOfMultipleNftsToDifferentWallets(
        address[] memory nfts,
        address[] memory to,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) external payable {
        require(nfts.length > 0, "BrewlabsNftTransfer: NFT not selected");
        require(
            nfts.length == tokenIds.length && nfts.length == to.length && nfts.length == amounts.length,
            "Invalid arguments"
        );

        _transferPerformanceFee();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (i >= transferLimit) break;
            if (IERC165(nfts[i]).supportsInterface(type(IERC1155).interfaceId)) {
                IERC1155(nfts[i]).safeTransferFrom(msg.sender, to[i], tokenIds[i], amounts[i], "");
            } else {
                IERC721(nfts[i]).safeTransferFrom(msg.sender, to[i], tokenIds[i]);
            }
        }
    }

    function _transferPerformanceFee() internal {
        require(msg.value >= performanceFee, "should pay small gas to compound or harvest");

        payable(treasury).transfer(performanceFee);
        if (msg.value > performanceFee) {
            payable(msg.sender).transfer(msg.value - performanceFee);
        }
    }

    function setServiceInfo(address _treasury, uint256 _fee) external onlyOwner {
        require(_treasury != address(0x0), "Invalid address");

        treasury = _treasury;
        performanceFee = _fee;

        emit ServiceInfoChanged(_treasury, _fee);
    }

    function setTransferLimitPerTx(uint256 _limit) external onlyOwner {
        transferLimit = _limit;

        emit TransferLimitChanged(transferLimit);
    }

    receive() external payable {}
}
