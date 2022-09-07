const { ethers } = require("ethers");
const csvToJson = require("convert-csv-to-json");
const { keccak256, solidityKeccak256 } = require("ethers/lib/utils");
const { MerkleTree } = require("merkletreejs");
const fs = require("fs");

const snapshot = csvToJson.fieldDelimiter(",").getJsonFromCsv("scripts/snapshot.csv");

const generateMerkleTree = () => {
  const leaves = snapshot.map((user) =>
    solidityKeccak256(
      ["address", "uint256"],
      [user.address, ethers.utils.parseUnits(user.amount, 18)._hex]
    )
  );
  const tree = new MerkleTree(leaves, keccak256, { sort: true });

  const merkleRoot = tree.getHexRoot();
  console.log(`Merkle Tree:\n`, tree.toString());
  console.log(`Merkle Root: ${merkleRoot}`);
};

const generateProof = (address, amount) => {
  const leaves = snapshot.map((user) =>
    solidityKeccak256(
      ["address", "uint256"],
      [user.address, ethers.utils.parseUnits(user.amount, 9)._hex]
    )
  );
  const tree = new MerkleTree(leaves, keccak256, { sort: true });

  const hexProof = tree.getHexProof(
    solidityKeccak256(["address", "uint256"], [address, ethers.utils.parseUnits(amount, 9)._hex])
  );
  console.log(`Merkle Proof: - ${address}, ${amount}`, hexProof);
};

const storeJSON = async () => {
  fs.writeFileSync("scripts/snapshot.json", JSON.stringify(snapshot, null, 4));
};

generateMerkleTree()
storeJSON();
