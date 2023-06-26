// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721, ERC721Enumerable, IERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MockErc721 is ERC721Enumerable {
    uint256 public supply;
    mapping(uint256 => uint256) private rarities;

    constructor() ERC721("Test Nft", "TNFT") {}

    function mint(address _to, uint256 _rarity) external {
        supply++;

        rarities[supply] = _rarity;
        _safeMint(_to, supply);
    }

    function burn(uint256 _tokenId) external {
        _burn(_tokenId);
    }

    function rarityOf(uint256 tokenId) external view returns (uint256) {
        return rarities[tokenId];
    }

    function tBalanceOf(address owner) external view returns (uint256) {
        return balanceOf(owner);
    }

    function tTokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256) {
        return tokenOfOwnerByIndex(owner, index);
    }

}
