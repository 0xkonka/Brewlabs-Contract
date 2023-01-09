// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockErc20 is ERC20 {
    uint8 internal _decimals;

    constructor(uint8 __decimals) ERC20("TEST", "test") {
        _decimals = __decimals;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public virtual {
        _burn(from, amount);
    }
}
