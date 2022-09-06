const { keccak256, solidityKeccak256 } = require("ethers/lib/utils");
const { MerkleTree } = require("merkletreejs");

const whitelist = [
  { address: "address1", amount: 1 },
  { address: "address2", amount: 21 },
  { address: "address3", amount: 41 },
];

const generateMerkleTree = () => {
  const leaves = whitelist.map((user) =>
    solidityKeccak256(["address", "uint256"], [user.address, user.amount])
  );
  const tree = new MerkleTree(leaves, keccak256, { sort: true });

  const merkleRoot = tree.getHexRoot();
  console.log(`Merkle Tree:\n`, tree.toString());
  console.log(`Merkle Root: ${merkleRoot}`);
};

const generateProof = (address, amount) => {
  const leaves = whitelist.map((user) =>
    solidityKeccak256(["address", "uint256"], [user.address, user.amount])
  );
  const tree = new MerkleTree(leaves, keccak256, { sort: true });

  const hexProof = tree.getHexProof(solidityKeccak256(["address", "uint256"], [address, amount]));
  console.log(`Merkle Proof: - ${address}, ${amount}`, hexProof);
};

// generateMerkleTree()
// generateProof("address1")
