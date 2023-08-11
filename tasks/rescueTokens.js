const { task, types } = require("hardhat/config");
const { formatEther, formatUnits, parseEther } = require("ethers/lib/utils.js");

/**
 * @note
 * npx hardhat rescue-token --count 10 --network eth_mainnet
 * yarn rescue-token --count 10
 **/
const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));
task("rescue-token", "Make transactions")
  .addParam("count", "number to transactions", 10, types.int)
  .setAction(async function ({ count }, hre, _) {
    const { getUnnamedAccounts, deployments, ethers } = hre;

    const {deploy} = deployments;
    let accounts = await getUnnamedAccounts();
    let account = accounts[0];
    console.log(`account : `, account);

    for (let i = 0; i < count; i++) {
      try {
        let nonce = await ethers.provider.getTransactionCount(account, "latest");
        console.log("nonce: ", nonce);
        return;
        if (nonce <= 487) {
            let gasPrice = await ethers.provider.getGasPrice();
            gasPrice = gasPrice.mul(110).div(100);

            let fee = gasPrice.mul(21000);
            console.log(`gasPrice: ${formatUnits(gasPrice, 9)} gwei, fee: ${formatEther(fee)}`);

            const txData = {
                from: account,
                to: account,
                value: "0",
                nonce,
                gasLimit: "21000",
                gasPrice,
            };
            const signer = await ethers.getSigner(account);
            let tx = await signer.sendTransaction(txData);
            console.log("Waiting tx confirmations");
            await tx.wait();
        } else {
            let deployed = await deploy('Claim', {
                from: account,
                args: [],
                log: true,
            });
            console.log("==> Contract: ", deployed.address)
            await sleep(10)
            let contractInstance = await ethers.getContractAt("Claim", deployed.address)
            let owner = await contractInstance.owner();
            console.log(owner)
            return;
        }
      } catch (e) {
        console.log(e);
      }
    }
  });
