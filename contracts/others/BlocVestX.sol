// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract BlocVestX is ERC20Burnable, Ownable {
    mapping(address => bool) isMinter;

    event AddMinter(address minter);
    event RemoveMinter(address minter);

    modifier onlyMinter() {
        require(isMinter[msg.sender], "not minter");
        _;
    }

    constructor() ERC20("BlocVestX", "BVSTX") {}

    function mint(address _to, uint256 _amount) external onlyMinter {
        _mint(_to, _amount);
    }

    function addMinter(address _minter) external onlyOwner {
        isMinter[_minter] = true;
        emit AddMinter(_minter);
    }

    function removeMinter(address _minter) external onlyOwner {
        isMinter[_minter] = false;
        emit RemoveMinter(_minter);
    }
}
