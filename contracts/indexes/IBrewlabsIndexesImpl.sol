// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IBrewlabsIndexesImpl {
    function initialize(
        IERC20[] memory _tokens,
        IERC721 _nft,
        address _router,
        address[][] memory _paths,
        address _owner
    ) external;
}
