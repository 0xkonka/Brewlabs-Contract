// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract BrewlabsStandardToken is ERC20, Ownable {
    bool private isInitialized;

    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;

    constructor() ERC20("BrewlabsStandardToken", "BST") {}

    function initialize(
        string memory __name,
        string memory __symbol,
        uint8 __decimals,
        uint256 __totalSupply,
        address __deployer
    ) external {
        require(!isInitialized, "Already initialized");
        require(owner() == address(0x0) || msg.sender == owner(), "Not allowed");

        isInitialized = true;
        _name = __name;
        _symbol = __symbol;
        _decimals = __decimals;

        _mint(__deployer, __totalSupply);
        _transferOwnership(__deployer);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
