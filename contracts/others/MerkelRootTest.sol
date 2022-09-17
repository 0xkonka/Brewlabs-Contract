// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/**
 * @author Brewlabs
 * This contract has been developed by brewlabs.info
 */
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract MerkelRootTest is Ownable {
  bytes32 private merkleRoot;

  function check(
    address _addr,
    uint256 _max,
    bytes32[] memory _merkleProof
  ) external view returns (bool) {
    require(merkleRoot != "", "Migration not enabled");

    // Verify the merkle proof.
    bytes32 leaf = keccak256(abi.encodePacked(_addr, _max));
    return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
  }

  function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
    merkleRoot = _merkleRoot;
  }
  receive() external payable {}
}
