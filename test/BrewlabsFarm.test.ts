import { expectRevert, time } from "@openzeppelin/test-helpers";
import { expect } from "chai";
import { network, ethers, upgrades, artifacts } from "hardhat";

import { abi as UniRouterAbi } from "../artifacts/contracts/libs/IUniRouter02.sol/IUniRouter02.json"
import { abi as Erc20Abi }  from "../artifacts/@openzeppelin/contracts/token/ERC20/IERC20.sol/IERC20.json"

import MockErc20 from "../artifacts/contracts/mocks/MockErc20.sol/MockErc20.json"

const router_addr = "0x10ed43c718714eb63d5aa57b78b54704e256024e";
const reward_token_addr = "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7";

describe("BrewlabsFarm", () => {
  let uniRouter, rewardToken, lp1, lp2, lp3, brewlabsFarm;
  let alice, bob, dev, deployer;

  before(async () => {
    [deployer, alice, bob, dev] = await ethers.getSigners();
    console.log({
      deployer: deployer.address,
      alice: alice.address,
      bob: bob.address,
      dev: dev.address,
    });

    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [router_addr],
    });
    const uniRouterSigner = await ethers.provider.getSigner(router_addr);
    uniRouter = new ethers.Contract(router_addr, UniRouterAbi, uniRouterSigner);

    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [reward_token_addr],
    })
    const rewardTokenSigner = await ethers.provider.getSigner(reward_token_addr);
    rewardToken = new ethers.Contract(reward_token_addr, Erc20Abi, rewardTokenSigner);

    const LPToken = await ethers.getContractFactory("MockBEP20", deployer);
    lp1 = await LPToken.deploy("LPToken", "LP1", "1000000");
    lp2 = await LPToken.deploy("LPToken", "LP2", "1000000");
    lp3 = await LPToken.deploy("LPToken", "LP3", "1000000");

  });

  it("Should assign the total supply of tokens to the owner", async () => {
    const ownerBalance = await lp1.balanceOf(deployer.address);
    expect(await lp1.totalSupply()).to.equal(ownerBalance);
  })
});