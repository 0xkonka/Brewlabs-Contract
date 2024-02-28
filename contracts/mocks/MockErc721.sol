// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockErc721 is ERC721, Ownable {
    uint256 public supply;

    constructor() ERC721("Test Nft", "TNFT") {}

    function mint(address _to) external returns (uint256) {
        supply++;
        _safeMint(_to, supply);

        return supply;
    }

    function burn(uint256 _tokenId) external {
        _burn(_tokenId);
    }
}
