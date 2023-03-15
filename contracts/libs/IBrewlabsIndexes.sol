// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBrewlabsIndexes {
   function initialize(
        IERC20[2] memory _tokens,
        IERC721 _nft,
        address _router,
        address[][2] memory _paths
    ) external;
    
    function NUM_TOKENS() external view returns (uint8);
    function tokens(uint256 index) external view returns (address);
    function nftInfo(uint256 _tokenId) external view returns (uint256[] memory, uint256);
}
