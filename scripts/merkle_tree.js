const { ethers } = require("ethers");
const csvToJson = require("convert-csv-to-json");
const { keccak256, solidityKeccak256 } = require("ethers/lib/utils");
const { MerkleTree } = require("merkletreejs");
const fs = require("fs");
const BigNumber = require("bignumber.js");

const { abi } = require("../artifacts/contracts/others/MerkelRootTest.sol/MerkelRootTest.json");

const snapshot = csvToJson.fieldDelimiter(",").getJsonFromCsv("scripts/snapshot.csv");

const generateMerkleTree = () => {
  const leaves = snapshot.map((user) => {
    return solidityKeccak256(
      ["address", "uint256"],
      [
        user.address,
        ethers.utils.parseUnits(+user.amount > 1 ? (+user.amount).toString() : (+user.amount).toFixed(9), 9)._hex,
      ]
    )
  }
    
  );
  const tree = new MerkleTree(leaves, keccak256, { sort: true });

  const leaves1 = snapshot.map((user) =>
    solidityKeccak256(
      ["address", "uint256"],
      [
        user.address,
        ethers.utils.parseUnits(+user.claimAmt > 1 ? (+user.claimAmt).toString() : (+user.claimAmt).toFixed(9), 9)._hex,
      ]
    )
  );
  const tree1 = new MerkleTree(leaves1, keccak256, { sort: true });

  let sum = new BigNumber("0");
  let claim = new BigNumber("0");
  snapshot.forEach((user) => {
    if (user.address !== "0x000000000000000000000000000000000000dead") {
      sum = sum.plus(user.amount);
      claim = claim.plus(user.claimAmt)
    }
  });
  console.log(`total: ${sum.toString()}`);
  console.log(`expected: `, claim.toString());

  const merkleRoot = tree.getHexRoot();
  const claimMerkleRoot = tree1.getHexRoot();
  // console.log(`Merkle Tree:\n`, tree.toString());
  console.log(`Merkle Root: ${merkleRoot}`);
  console.log(`Claim Merkle Root: ${claimMerkleRoot}`);
};

const generateProof = (address, amount) => {
  const leaves = snapshot.map((user) =>
    solidityKeccak256(
      ["address", "uint256"],
      [
        user.address,
        ethers.utils.parseUnits(+user.amount > 1 ? (+user.amount).toString() : (+user.amount).toFixed(9), 9)._hex,
      ]
    )
  );
  const tree = new MerkleTree(leaves, keccak256, { sort: true });

  const hexProof = tree.getHexProof(
    solidityKeccak256(
      ["address", "uint256"],
      [address, ethers.utils.parseUnits(+amount > 1 ? (+amount).toString() : (+amount).toFixed(9), 9)._hex]
    )
  );
  // console.log(`Merkle Proof: - ${address}, ${amount}`, hexProof);
  return hexProof;
};

const checkProof = async () => {
  const contract = new ethers.Contract(
    "0xC0Afa0590cAc6742F87094376C270C9C2BBfEcb4",
    abi,
    new ethers.providers.JsonRpcProvider("https://data-seed-prebsc-1-s1.binance.org:8545")
  );

  for (let i = 0; i < snapshot.length; i++) {
    user = snapshot[i];
    const proof = generateProof(user.address, user.amount);
    const result = await contract.check(
      user.address,
      ethers.utils.parseUnits(+user.amount > 1 ? (+user.amount).toString() : (+user.amount).toFixed(9), 9),
      proof
    );
    console.log(user.address, user.amount, result);
  }
};

const storeJSON = async () => {
  fs.writeFileSync("scripts/snapshot.json", JSON.stringify(snapshot, null, 4));
};

generateMerkleTree();
storeJSON();

// checkProof();
