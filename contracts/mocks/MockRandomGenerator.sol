// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract MockRandomGenerator is Ownable {
    mapping(address => bool) public admins;

    uint256 public randomSeed;

    /**
     * @notice Constructor
     * @dev RandomNumberGenerator must be deployed prior to this contract
     */
    constructor() {
        randomSeed = uint256(keccak256(abi.encode("testing vrf", block.number)));
        admins[msg.sender] = true;
    }

    function random() public view returns (uint256) {
        require(randomSeed != 0, "Invalid seed");
        return uint256(keccak256(abi.encode(randomSeed, block.timestamp, blockhash(block.number - 1))));
    }

    /**
     * Requests randomness
     */
    function genRandomNumber() public returns (uint256 requestId) {
        randomSeed = uint256(keccak256(abi.encode("testing", randomSeed, blockhash(block.number-1), block.timestamp)));        
    }

    function setAdmin(address _account, bool _isAdmin) external onlyOwner {
        admins[_account] = _isAdmin;
    }
}
