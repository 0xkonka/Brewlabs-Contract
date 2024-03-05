// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockErc1155 is ERC1155, Ownable {
    string public name = "Test Nft";
    string public symbol = "TNFT";
    uint256 public supply;

    constructor() ERC1155("") {}

    function mint(address _to, uint256 _amount) external returns (uint256) {
        supply++;
        _mint(_to, supply, _amount, "");

        return supply;
    }

    function mintBatch(address _to, uint256[] memory _amounts) external {
        for (uint256 i = 0; i < _amounts.length; i++) {
            supply++;
            _mint(_to, supply, _amounts[i], "");
        }
    }

    function burn(uint256 _tokenId, uint256 _amount) external {
        _burn(msg.sender, _tokenId, _amount);
    }
}
