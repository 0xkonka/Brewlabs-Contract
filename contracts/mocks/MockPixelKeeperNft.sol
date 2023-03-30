// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockPixelKeeperNft is ERC721 {
    uint256 public supply;
    mapping(uint256 => uint256) public rarityOfItem;

    constructor() ERC721("Mock TPK", "MTPK") {}

    function mint(uint256 _rarity, address _to) external {
        supply++;
        rarityOfItem[supply] = _rarity;

        _safeMint(_to, supply);
    }

    function burn(uint256 _tokenId) external {
        _burn(_tokenId);
    }
}
