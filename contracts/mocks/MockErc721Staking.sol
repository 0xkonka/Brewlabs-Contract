// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract MockErc721Staking is ERC721Holder {
    IERC721 public stakingNft;

    constructor(IERC721 _nft) {
        stakingNft = _nft;
    }

    function stake(uint256 tokenId) external {
        stakingNft.safeTransferFrom(msg.sender, address(this), tokenId, "");
    }
}
