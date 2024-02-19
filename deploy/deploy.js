const path = require('path')
const Utils = require('../Utils');
const hre = require("hardhat")

const { abi: FarmFactoryAbi } = require("../artifacts/contracts/farm/BrewlabsFarmFactory.sol/BrewlabsFarmFactory.json")
const { abi: IndexFactoryAbi } = require("../artifacts/contracts/indexes/BrewlabsIndexFactory.sol/BrewlabsIndexFactory.json")

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

module.exports = async ({ getUnnamedAccounts, deployments, ethers, network }) => {

    try {
        const { deploy } = deployments;
        const accounts = await getUnnamedAccounts();
        let account = accounts[0];

        Utils.infoMsg(" ------------------------------------------------------------------------------- ")
        Utils.infoMsg(" --------------------------- Deploying Brewlabs Contracts ------------------- ")
        Utils.infoMsg(" ------------------------------------------------------------------------------- ")
        Utils.infoMsg(` Deployer:  ${account}`)

        const config = {
            tokenFreezer: false,
            pairFreezer: false,

            configure: false,
            nftTransfer: false,
            teamlocker: false,

            index: false,
            indexNft: false,
            deployerNft: false,
            indexData: false,
            indexImpl: false,
            indexFactory: false,
            flaskNft: false,
            nftStaking: false,

            farm: false,
            farmImpl: false,
            dualFarmImpl: false,
            farmFactory: false,
            oldFarm: false,

            tokenImpl: false,
            tokenFactory: false,

            staking: false,
            lockupStaking: false,
            lockupStakingV2: false,
            lockupFixed: false,

            multi: false,
            multiLockup: false,
            liquidityMgr: false,
            brewsLocker: false,

            // others
            treasury: false,
            vesting: false,
            buffetLocker: false,
            blvtVest: false,
            kodi: false,
            kodiTreasury: false,
            oracle: false,
            twapOracle: false,

            other: false,
        }

        if (config.other) {
            Utils.infoMsg("Deploying WarPigsTreasury contract");

            let deployed = await deploy('WarPigsTreasury', {
                from: account,
                args: [],
                log: true,
            });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            let contractInstance = await ethers.getContractAt("WarPigsTreasury", deployedAddress)
            const res = await contractInstance.initialize(
                "0x8466BB37bde898E0820E0d9CFe2EB68fbB90cE9b", // _token
                "0x0000000000000000000000000000000000000000", // _dividendToken
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2                
            )
            console.log('initialize BrewlabsTreasury', res)

            // verify
            await sleep(60);
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/others/WarPigsTreasury.sol:WarPigsTreasury",
                constructorArguments: [],
            })
        }

        if (config.indexNft) {
            Utils.infoMsg("Deploying BrewlabsIndexNft contract");
            let deployed = await deploy('BrewlabsIndexNft',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            let contractInstance = await ethers.getContractAt("BrewlabsIndexNft", deployedAddress)
            await contractInstance.setTokenBaseURI("https://maverickbl.mypinata.cloud/ipfs/QmUaFYco7KfL9Yz3fWqhygAzw7A1RaSkh6nV75NBu5a7CV", true);

            // verify
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/indexes/BrewlabsIndexNft.sol:BrewlabsIndexNft",
                constructorArguments: [],
            })
        }

        if (config.deployerNft) {
            Utils.infoMsg("Deploying BrewlabsDeployerNft contract");
            let deployed = await deploy('BrewlabsDeployerNft',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // let contractInstance = await ethers.getContractAt("BrewlabsDeployerNft", deployedAddress)
            // await contractInstance.setTokenBaseURI("https://maverickbl.mypinata.cloud/ipfs/QmUaFYco7KfL9Yz3fWqhygAzw7A1RaSkh6nV75NBu5a7CV", true);

            // verify
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/indexes/BrewlabsDeployerNft.sol:BrewlabsDeployerNft",
                constructorArguments: [],
            })
        }

        if (config.indexData) {
            Utils.infoMsg("Deploying BrewlabsIndexData contract");
            let deployed = await deploy('BrewlabsIndexData',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
        }

        if (config.indexImpl) {
            Utils.infoMsg("Deploying BrewlabsIndex contract");
            let deployed = await deploy('BrewlabsIndex',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
        }

        if (config.indexFactory) {
            Utils.infoMsg("Deploying BrewlabsIndexFactory contract");
            let implementation = "0xC3283Fc210Ba6c4C9597860D2f7b3aB99cD339A0"
            let indexNft = "0x1602fa38A7Fc0A9Fa166EcA5eF7416b1e7991c81"
            let deployerNft = "0x14FA731AED865Bef6d1C459894B8e5DC60D8e4c0"
            let payingToken = "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d"

            if (implementation === "") {
                Utils.successMsg(`Implementation was not set`);
                return
            }
            if (indexNft === "") {
                Utils.successMsg(`Index NFT was not set`);
                return
            }
            if (deployerNft === "") {
                Utils.successMsg(`Deployer NFT was not set`);
                return
            }
            if (payingToken === "") {
                Utils.successMsg(`Paying token was not set`);
                return
            }

            let deployed = await deploy('BrewlabsIndexFactory',
                {
                    from: account,
                    args: [],
                    log: true,
                    proxy: {
                        proxyContract: "OpenZeppelinTransparentProxy",
                        execute: {
                            init: {
                                methodName: "initialize",
                                args: [
                                    implementation,
                                    indexNft,
                                    deployerNft,
                                    payingToken,
                                    ethers.utils.parseUnits("0", 18),
                                    "0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F", // default owner of indexes
                                ],
                            }
                        },
                    },
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsIndexFactory", deployedAddress)
            let res = await contractInstance.addToWhitelist(account);
            await res.wait();

            contractInstance = await ethers.getContractAt("BrewlabsIndexNft", indexNft);
            res = await contractInstance.setAdmin(deployedAddress);
            await res.wait();

            contractInstance = await ethers.getContractAt("BrewlabsDeployerNft", deployerNft);
            res = await contractInstance.setAdmin(deployedAddress);
            await res.wait();

            // verify
            // await hre.run("verify:verify", {
            //     address: deployedAddress,
            //     contract: "contracts/indexes/BrewlabsIndexFactory.sol:BrewlabsIndexFactory",
            //     constructorArguments: [],
            // })
        }

        if (config.index) {
            let factory = ""
            if (factory === "") {
                Utils.successMsg(`factory was not set`);
                return
            }
            Utils.infoMsg("Creating BrewlabsIndex contract via factory");
            let contractInstance = await ethers.getContractAt("BrewlabsIndexFactory", factory)
            let res = await contractInstance.createBrewlabsIndex(
                [
                    "0xAD6742A35fB341A9Cc6ad674738Dd8da98b94Fb1", // token0
                    "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c", // token0
                    "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", // token1
                    "0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82", // token1
                ],
                200 // fee
            );
            res = await res.wait()

            const iface = new ethers.utils.Interface(IndexFactoryAbi);
            for (let i = 0; i < res.logs.length; i++) {
                try {
                    const log = iface.parseLog(tx.logs[i]);
                    if (log.name === "IndexCreated") {
                        Utils.successMsg(`Contract Address: ${log.args.index}`);
                        break;
                    }
                } catch (e) { }
            }
        }

        if (config.flaskNft) {
            Utils.infoMsg("Deploying RandomSeedGenerator contract");
            let randomGenerator = await deploy('RandomSeedGenerator',
                {
                    from: account,
                    args: [
                        "0xc587d9053cd1118f25F645F9E08BB98c9712A4EE",
                        "0x404460C6A5EdE2D891e8297795264fDe62ADBB75",
                        "0xba6e730de88d94a5510ae6613898bfb0c3de5d16e609c5b7da808747125506f7"
                    ],
                    log: false
                });
            Utils.successMsg(`Contract Address: ${randomGenerator.address}`);
            await sleep(30);

            Utils.infoMsg("Deploying BrewlabsFlaskNft contract");
            let flaskNft = await deploy('BrewlabsFlaskNft',
                {
                    from: account,
                    args: [randomGenerator.address],
                    log: false
                });

            Utils.successMsg(`Contract Address: ${flaskNft.address}`);

            let flaskNftInstance = await ethers.getContractAt("BrewlabsFlaskNft", flaskNft.address)
            await flaskNftInstance.setTokenBaseUri("https://maverickbl.mypinata.cloud/ipfs/QmaStvah11DH7moS822msJS5D7i4E4gYsPiZqrvMzsabEh");
            let tx = await flaskNftInstance.setFeeToken("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", true);
            await tx.wait()
            tx = await flaskNftInstance.setFeeToken("0x55d398326f99059fF775485246999027B3197955", true);
            await tx.wait()

            Utils.infoMsg("Deploying BrewlabsMirrorNft contract");
            let mirrorNft = await deploy('BrewlabsMirrorNft',
                {
                    from: account,
                    args: [flaskNft.address],
                    log: false
                });

            Utils.successMsg(`Contract Address: ${mirrorNft.address}`);

            let mirrorNftInstance = await ethers.getContractAt("BrewlabsMirrorNft", mirrorNft.address)
            tx = await mirrorNftInstance.setTokenBaseUri("https://maverickbl.mypinata.cloud/ipfs/QmcLtpxjWyvrTjqFBYoxdMmY2fRVquXyoP6rusr18kZ4Aj");
            await tx.wait()

            tx = await flaskNftInstance.setMirrorNft(mirrorNft.address);
            await tx.wait()

            let randomGeneratorInstance = await ethers.getContractAt("RandomSeedGenerator", randomGenerator.address)
            tx = await randomGeneratorInstance.setAdmin(flaskNft.address, true);
            await tx.wait()

            // verify
            await hre.run("verify:verify", {
                address: flaskNft.address,
                contract: "contracts/indexes/BrewlabsFlaskNft.sol:BrewlabsFlaskNft",
                constructorArguments: [randomGenerator.address],
            })
            await hre.run("verify:verify", {
                address: mirrorNft.address,
                contract: "contracts/indexes/BrewlabsMirrorNft.sol:BrewlabsMirrorNft",
                constructorArguments: [flaskNft.address],
            })
        }

        if (config.nftStaking) {
            let flaskNft = "0x680650268F8f307bC19b6DA6A9aaAe18D3bEF468";
            let mirrorNft = "0xBA43929FFEeFcf9e32081896DA6f332DAaE5bd5B";
            if (flaskNft === "" || mirrorNft === "") {
                Utils.errorMsg("Flask NFT or Mirror NFT were not be set");
                return
            }

            Utils.infoMsg("Deploying BrewlabsNftStaking contract");
            let deployed = await deploy('BrewlabsNftStaking',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let nftStakingAddr = deployed.address;
            Utils.successMsg(`Contract Address: ${nftStakingAddr}`);

            let contractInstance = await ethers.getContractAt("BrewlabsNftStaking", nftStakingAddr)
            let tx = await contractInstance.initialize(flaskNft, mirrorNft, "0x0000000000000000000000000000000000000000", "0")
            await tx.wait();

            tx = await contractInstance.setAdmin(flaskNft);
            await tx.wait();

            contractInstance = await ethers.getContractAt("BrewlabsMirrorNft", mirrorNft);
            tx = await contractInstance.setAdmin(nftStakingAddr)
            await tx.wait()

            contractInstance = await ethers.getContractAt("BrewlabsFlaskNft", flaskNft);
            tx = await contractInstance.setNftStakingContract(nftStakingAddr)
            await tx.wait()

            await hre.run("verify:verify", {
                address: nftStakingAddr,
                contract: "contracts/BrewlabsNftStaking.sol:BrewlabsNftStaking",
                constructorArguments: [],
            })
        }

        if (config.tokenImpl) {
            Utils.infoMsg("Deploying BrewlabsStandardToken contract");
            let deployed = await deploy('BrewlabsStandardToken',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);


            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/token/BrewlabsStandardToken.sol:BrewlabsStandardToken",
                constructorArguments: [],
            })
        }

        if (config.tokenFactory) {
            Utils.infoMsg("Deploying BrewlabsTokenFactory contract");
            let implementation = ""
            let payingToken = "0x0000000000000000000000000000000000000000"

            if (implementation === "") {
                Utils.successMsg(`Implementation was not set`);
                return
            }
            if (payingToken === "") {
                Utils.successMsg(`Paying token was not set`);
                return
            }

            let deployed = await deploy('BrewlabsTokenFactory',
                {
                    from: account,
                    args: [],
                    log: true,
                    proxy: {
                        proxyContract: "OpenZeppelinTransparentProxy",
                        execute: {
                            init: {
                                methodName: "initialize",
                                args: [
                                    implementation,
                                    payingToken,
                                    ethers.utils.parseUnits("1", 18),
                                    "0x78Eb67C73EBe18460986910C00B3A1365b402CC7", // default owner of indexes
                                ],
                            }
                        },
                    },
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)

            // verify
            // await hre.run("verify:verify", {
            //     address: deployedAddress,
            //     contract: "contracts/token/BrewlabsTokenFactory.sol:BrewlabsTokenFactory",
            //     constructorArguments: [],
            // })
        }

        if (config.farmImpl) {
            Utils.infoMsg("Deploying BrewlabsFarmImpl contract");
            let deployed = await deploy('BrewlabsFarmImpl',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
        }

        if (config.dualFarmImpl) {
            Utils.infoMsg("Deploying BrewlabsDualFarmImpl contract");
            let deployed = await deploy('BrewlabsDualFarmImpl',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
            await sleep(60);

            // verify
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/farm/BrewlabsDualFarmImpl.sol:BrewlabsDualFarmImpl",
                constructorArguments: [],
            });
        }

        if (config.farmFactory) {
            Utils.infoMsg("Deploying BrewlabsFarmFactory contract");
            let implementation = "0x4899e09444f18B04207b8f61beC101f1658D4e76"
            let payingToken = "0x55d398326f99059fF775485246999027B3197955"

            if (implementation === "") {
                Utils.successMsg(`Implementation was not set`);
                return
            }
            if (payingToken === "") {
                Utils.successMsg(`Paying token was not set`);
                return
            }

            let deployed = await deploy('BrewlabsFarmFactory',
                {
                    from: account,
                    args: [],
                    log: true,
                    proxy: {
                        proxyContract: "OpenZeppelinTransparentProxy",
                        execute: {
                            init: {
                                methodName: "initialize",
                                args: [
                                    implementation,
                                    payingToken,
                                    ethers.utils.parseUnits("1600", 18),
                                    "0xE1f1dd010BBC2860F81c8F90Ea4E38dB949BB16F", // default owner of indexes
                                ],
                            }
                        },
                    },
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsFarmFactory", deployedAddress)
            let res = await contractInstance.addToWhitelist(account);
            await res.wait();

            // verify
            // await hre.run("verify:verify", {
            //     address: deployedAddress,
            //     contract: "contracts/farm/BrewlabsFarmFactory.sol:BrewlabsFarmFactory",
            //     constructorArguments: [],
            // })
        }

        if (config.farm) {
            let factory = "0xe8F5d6E471CDd8Bc1Ec180DD2bf31cF16A8b72cc"
            if (factory === "") {
                Utils.successMsg(`factory was not set`);
                return
            }
            Utils.infoMsg("Creating BrewlabsFarmImpl contract via factory");
            let contractInstance = await ethers.getContractAt("BrewlabsFarmFactory", factory)
            let res = await contractInstance.createBrewlabsFarm(
                "0xAD6742A35fB341A9Cc6ad674738Dd8da98b94Fb1", // LP
                "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c", // reward token
                "0x0000000000000000000000000000000000000000", // dividend token
                ethers.utils.parseUnits("1", 18), // reward per block                
                0, // deposit fee
                0, // withdraw fee
                false // has dividend
            );
            res = await res.wait()

            const iface = new ethers.utils.Interface(FarmFactoryAbi);
            for (let i = 0; i < res.logs.length; i++) {
                try {
                    const log = iface.parseLog(tx.logs[i]);
                    if (log.name === "FarmCreated") {
                        Utils.successMsg(`Contract Address: ${log.args.farm}`);
                        break;
                    }
                } catch (e) { }
            }
        }

        if (config.configure) {
            Utils.infoMsg("Deploying BrewlabsConfig contract");

            let deployed = await deploy("BrewlabsConfig", {
                from: account,
                args: [],
                log: true,
                proxy: {
                    proxyContract: "OpenZeppelinTransparentProxy",
                    execute: {
                        init: {
                            methodName: "initialize",
                            args: [],
                        }
                    },
                },
            });
            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // verify
            await sleep(60);
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsConfig.sol:BrewlabsConfig",
                constructorArguments: [],
            })
        }

        if (config.teamlocker) {
            Utils.infoMsg("Deploying BrewlabsTeamLocker contract");

            let deployed = await deploy('BrewlabsTeamLocker', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsTeamLocker.sol:BrewlabsTeamLocker",
                constructorArguments: [],
            })
        }

        if (config.nftTransfer) {
            Utils.infoMsg("Deploying BrewlabsNftTransfer contract");

            let deployed = await deploy("BrewlabsNftTransfer", {
                from: account,
                args: [],
                log: true,
            });
            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // verify
            // await sleep(60);
            // await hre.run("verify:verify", {
            //     address: deployedAddress,
            //     contract: "contracts/BrewlabsNftTransfer.sol:BrewlabsNftTransfer",
            //     constructorArguments: [],
            // }) 
        }

        if (config.oracle) {
            Utils.infoMsg("Deploying BrewlabsPriceOracle contract");
            let wbnb;
            switch (network.config.chainId) {
                case 1:
                    wbnb = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" // mainnet
                    break;
                case 5:
                    wbnb = "0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6" // goerli testnet
                    break;
                case 56:
                    wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c" // bsc mainnet
                    break;
                case 97:
                    wbnb = "0xae13d989dac2f0debff460ac112a837c89baa7cd" // bsc testnet
                    break;
                default:
                    Utils.errorMsg(`Not support ${network.config.chainId}`)
            }

            let deployed = await deploy('BrewlabsPriceOracle', {
                from: account,
                args: [wbnb],
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsPriceOracle", deployedAddress)

            await sleep(30)
            let tx
            if (network.config.chainId === 1) {
                // set usdc price
                tx = await contractInstance.setDirectPrice("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", ethers.utils.parseUnits("1", 18));
                await tx.wait()
                // set eth chainlink feed (eth-usd)                
                tx = await contractInstance.setAggregators([wbnb], ["0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"])
                await tx.wait()
            } else if (network.config.chainId === 5) {
                // set usdc price
                tx = await contractInstance.setDirectPrice("0xD87Ba7A50B2E7E660f678A895E4B72E7CB4CCd9C", ethers.utils.parseUnits("1", 18));
                await tx.wait()
                // set bnb chainlink feed (bnb-usd)
                tx = await contractInstance.setAggregators([wbnb], ["0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e"])
                await tx.wait()
            } else if (network.config.chainId === 56) {
                // set busd price
                tx = await contractInstance.setDirectPrice("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", ethers.utils.parseUnits("1", 18));
                await tx.wait()
                // set bnb chainlink feed (bnb-usd)                
                tx = await contractInstance.setAggregators([wbnb], ["0x0567f2323251f0aab15c8dfb1967e4e8a7d42aee"])
                await tx.wait()
            } else if (network.config.chainId === 97) {
                // set busd price
                tx = await contractInstance.setDirectPrice("0x2995bD504647b5EeE414A78be1d7b24f49f00FFE", ethers.utils.parseUnits("1", 18));
                await tx.wait()
                // set bnb chainlink feed (bnb-usd)
                tx = await contractInstance.setAggregators([wbnb], ["0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526"])
                await tx.wait()

                Utils.infoMsg("Deploying BrewlabsTwapOracle contract");
                let twapDeployed = await deploy('BrewlabsTwapOracle', {
                    from: account,
                    args: [
                        "0xB37d9c39d6A3873Dca3CBfA01D795a03f41b7298", // pair
                        14400, // period
                        1660708623, // startTime
                    ],
                    log: false
                });

                // verify
                await sleep(30)
                await hre.run("verify:verify", {
                    address: twapDeployed.address,
                    contract: "contracts/BrewlabsTwapOracle.sol:BrewlabsTwapOracle",
                    constructorArguments: [
                        "0xB37d9c39d6A3873Dca3CBfA01D795a03f41b7298", // pair
                        14400, // period
                        1660708623, // startTime
                    ],
                })
            }
            console.log('initialized BrewlabsPriceOracle')

            // verify
            await sleep(30)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsPriceOracle.sol:BrewlabsPriceOracle",
                constructorArguments: [wbnb],
            })
        }

        if (config.twapOracle) {
            Utils.infoMsg("Deploying BrewlabsTwapOracle contract");

            let deployed = await deploy('BrewlabsTwapOracle', {
                from: account,
                args: [
                    "0x2C97b52D9390590ef0Dd4346188d82431a9CdE88", // pair
                    14400, // period
                    1666137600, // startTime                    
                ],
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // verify
            await sleep(30)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsTwapOracle.sol:BrewlabsTwapOracle",
                constructorArguments: [
                    "0x2C97b52D9390590ef0Dd4346188d82431a9CdE88", // pair
                    14400, // period
                    1666137600, // startTime
                ],
            })
        }

        if (config.pairFreezer) {
            Utils.infoMsg("Deploying BrewlabsPairLocker implementation");
            let deployed = await deploy('BrewlabsPairLocker',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let implementation = deployed.address;
            Utils.successMsg(`Implementation Address: ${implementation}`);

            Utils.infoMsg("Deploying BrewlabsPairFreezer contract");
            deployed = await deploy('BrewlabsPairFreezer',
                {
                    from: account,
                    args: [implementation],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            if (network.config.chainId == 97) {
                let contractInstance = await ethers.getContractAt("BrewlabsPairFreezer", deployedAddress)
                await contractInstance.setTreasury("0x885A73F551FcC946C688eEFbC10023f4B7Cc48f3")
            }

            // // verify
            // await sleep(60)
            // await hre.run("verify:verify", {
            //     address: deployedAddress,
            //     contract: "contracts/BrewlabsPairFreezer.sol:BrewlabsPairFreezer",
            //     constructorArguments: [implementation],
            // })
        }

        if (config.tokenFreezer) {
            Utils.infoMsg("Deploying BrewlabsTokenLocker implementation");
            let deployed = await deploy('BrewlabsTokenLocker',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let implementation = deployed.address;
            Utils.successMsg(`Implementation Address: ${implementation}`);

            Utils.infoMsg("Deploying BrewlabsTokenFreezer contract");
            deployed = await deploy('BrewlabsTokenFreezer',
                {
                    from: account,
                    args: [implementation],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);


            if (network.config.chainId == 97) {
                let contractInstance = await ethers.getContractAt("BrewlabsTokenFreezer", deployedAddress)
                await contractInstance.setTreasury("0x885A73F551FcC946C688eEFbC10023f4B7Cc48f3")
            }

            // // verify
            // await sleep(60)
            // await hre.run("verify:verify", {
            //     address: deployedAddress,
            //     contract: "contracts/BrewlabsTokenFreezer.sol:BrewlabsTokenFreezer",
            //     constructorArguments: [implementation],
            // })
        }

        if (config.treasury) {
            Utils.infoMsg("Deploying BrewlabsTreasury contract");
            let deployed = await deploy('BrewlabsTreasury',
                {
                    from: account,
                    args: [],
                    log: false
                });

            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsTreasury", deployedAddress)
            const res = await contractInstance.initialize(
                "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7", // _token (BREWS)
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _dividendToken (BUSD)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7",
                ],
                [
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                ],
                [
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7",
                ],
            )
            console.log('initialize BrewlabsTreasury', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsTreasury.sol:BrewlabsTreasury",
                constructorArguments: [],
            })
        }

        if (config.oldFarm) {
            Utils.infoMsg("Deploying BrewlabsFarm contract");
            const _hasDividend = false;
            const _rewardPerBlock = ethers.utils.parseUnits("0.000083714036868", 18)
            const args = [
                "0xCbD34BE8b8deB2fB6f5CC5bc14a37c2398Db5320",
                "0x0000000000000000000000000000000000000000",
                _rewardPerBlock,
                _hasDividend,
            ];
            let deployed = await deploy('BrewlabsFarm',
                {
                    from: account,
                    args: args,
                    log: false
                });
            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            // add farm contract to config
            // let configInstance = await ethers.getContractAt("BrewlabsConfig", "0x60309cDed48575278f77d1Cb6b45e15693700b75")
            // let tx = await configInstance.regFarm(deployedAddress)
            // await tx.wait();

            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsFarm", deployedAddress)
            await contractInstance.add(
                1000,                                                   // allocPoint
                "0xa3d3c170a79b2c8eb773edffa3976716a42800a9",           // lp token address
                0,                                                      // deposit fee
                0,                                                      // withdraw fee 
                365,                                                    // duration
                false
            );

            // verify
            // await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/farm/BrewlabsFarm.sol:BrewlabsFarm",
                constructorArguments: args,
            })
        }

        if (config.staking) {
            Utils.infoMsg("Deploying BrewlabsStaking contract");

            let deployed = await deploy('BrewlabsStaking', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // await sleep(60)
            // add pool contract to config
            let configInstance = await ethers.getContractAt("BrewlabsConfig", "0xC440FF8B687E0132111B7437D236a4ec9ad2a45B")
            let tx = await configInstance.regPool(deployedAddress, false)
            await tx.wait();

            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsStaking", deployedAddress)
            const _hasDividend = true;
            const _rewardPerBlock = ethers.utils.parseUnits('2378234.398782343', 9)
            const res = await contractInstance.initialize(
                "0xf0D43f46Cea02bBb5E616bF6d795D4f8719cD80d", // _stakingToken
                "0xf0D43f46Cea02bBb5E616bF6d795D4f8719cD80d", // _earnedToken
                "0xf0D43f46Cea02bBb5E616bF6d795D4f8719cD80d", // _reflectionToken
                _rewardPerBlock,                              // _rewardPerBlock
                0,                                          // _depositFee (0.3%)
                100,                                          // _withdrawFee (1%)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
                [],
                "0x0000000000000000000000000000000000000000", // whitelist contract 
                _hasDividend,
            )

            console.log('initialize BrewlabsStaking', res)

            // verify
            // await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/pool/BrewlabsStaking.sol:BrewlabsStaking",
                constructorArguments: [],
            })
        }

        if (config.lockupStaking) {
            Utils.infoMsg("Deploying BrewlabsLockup contract");

            let deployed = await deploy('BrewlabsLockup', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            // add farm contract to config
            let configInstance = await ethers.getContractAt("BrewlabsConfig", "0x60309cDed48575278f77d1Cb6b45e15693700b75")
            let tx = await configInstance.regPool(deployedAddress, true)
            await tx.wait();

            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsLockup", deployedAddress)
            let res = await contractInstance.initialize(
                "0x4aeB2D0B318e5e8ac62D5A39EB3495974951f477", // _stakingToken 
                "0x4aeB2D0B318e5e8ac62D5A39EB3495974951f477", // _earnedToken 
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _reflectionToken 
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
                [
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x4aeB2D0B318e5e8ac62D5A39EB3495974951f477"
                ],
                "0x0000000000000000000000000000000000000000", // whitelist contract                                                 
            )
            console.log('initialize BrewlabsLockup', res)

            let _rate = ethers.utils.parseUnits('0.001426940639269406', 18)
            res = await contractInstance.addLockup(7, 10, 30, _rate, 0) // _duration, _depositFee, _withdrawFee, _rate
            await res.wait()

            // verify
            // await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/pool/BrewlabsLockup.sol:BrewlabsLockup",
                constructorArguments: [],
            })
        }

        if (config.lockupStakingV2) {
            Utils.infoMsg("Deploying BrewlabsLockupV2 contract");

            let deployed = await deploy('BrewlabsLockupV2', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsLockupV2", deployedAddress)
            const _rewardPerBlock = ethers.utils.parseUnits('1.1891', 4)
            const res = await contractInstance.initialize(
                "0x99459fE946B072E5211A6b01EA26BafABbf77aaa", // _stakingToken (LYST)
                "0x99459fE946B072E5211A6b01EA26BafABbf77aaa", // _earnedToken (LYST)
                "0x99459fE946B072E5211A6b01EA26BafABbf77aaa", // _reflectionToken (BUSD)
                _rewardPerBlock,                              // reward per block
                0,                                            // deposit fee
                100,                                           // withdraw fee
                30,                                           // lock duration (days)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
                [],
            )
            console.log('initialize BrewlabsLockupV2', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/pool/BrewlabsLockupV2.sol:BrewlabsLockupV2",
                constructorArguments: [],
            })
        }

        if (config.lockupFixed) {
            Utils.infoMsg("Deploying BrewlabsLockupFixed contract");

            let deployed = await deploy('BrewlabsLockupFixed', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsLockupFixed", deployedAddress)
            const res = await contractInstance.initialize(
                "0x1DF2C6DF4d4E7F3188487F4515587c5E8b75dbfa", // _stakingToken
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _earnedToken
                "0x1DF2C6DF4d4E7F3188487F4515587c5E8b75dbfa", // _reflectionToken
                "3472222222222",                              // reward per block
                0,                                            // deposit fee
                0,                                           // withdraw fee
                7,                                           // lock duration (days)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                "0x2c3B47f2f2Fcf159994B66dce0c6bdFA57942109", // oracle
                [],
                [],
            )
            console.log('initialize BrewlabsLockupFixed', res)

            // verify
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/pool/BrewlabsLockupFixed.sol:BrewlabsLockupFixed",
                constructorArguments: [],
            })

        }

        if (config.multi) {
            Utils.infoMsg("Deploying BrewlabsStakingMulti(SeTC) contract");

            let deployed = await deploy('BrewlabsStakingMulti', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)

            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsStakingMulti", deployedAddress)
            const _rewardPerBlock = ethers.utils.parseUnits("5.787037037", 18)
            const res = await contractInstance.initialize(
                "0x3B053c9ca46d69656c2492EECC79Ef8a21ACFfF7", // _stakingToken (SeTC)
                "0x3B053c9ca46d69656c2492EECC79Ef8a21ACFfF7", // _earnedToken (SeTC)
                [
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
                    "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",
                ], // _reflectionTokens (BUSD/BNB/BBTC/WETH)
                _rewardPerBlock,                              // _rewardPerBlock
                0,                                            // _depositFee (0%)
                200,                                          // _withdrawFee (2%)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
            )
            console.log('initialize BrewlabsStakingMulti(SeTC)', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/pool/BrewlabsStakingMulti.sol:BrewlabsStakingMulti",
                constructorArguments: [],
            })
        }

        if (config.multiLockup) {
            Utils.infoMsg("Deploying BrewlabsLockupMulti contract");

            let deployed = await deploy('BrewlabsLockupMulti', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            // add farm contract to config
            let configInstance = await ethers.getContractAt("BrewlabsConfig", "0x60309cDed48575278f77d1Cb6b45e15693700b75")
            let tx = await configInstance.regMultiPool(deployedAddress)
            await tx.wait();

            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsLockupMulti", deployedAddress)
            const _rewardPerBlock = ethers.utils.parseUnits('237.823439878234398782', 18)
            const res = await contractInstance.initialize(
                "0x606379220AB266bBE4b0FeF8469e6E602f295a84", // _stakingToken
                "0x606379220AB266bBE4b0FeF8469e6E602f295a84", // _earnedToken
                [
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                    "0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE",
                    "0xe7057B10E2B59F46D151588d9C8694B4b8328F44",
                ], // _reflectionToken 
                _rewardPerBlock,                              // reward per block
                0,                                            // deposit fee
                10,                                           // withdraw fee
                180,                                           // lock duration (days)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
            )
            console.log('initialize BrewlabsLockupMulti', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/pool/BrewlabsLockupMulti.sol:BrewlabsLockupMulti",
                constructorArguments: [],
            })
        }

        if (config.liquidityMgr) {
            Utils.infoMsg("Deploying BrewlabsLiquidityManager contract");

            let deployed = await deploy('BrewlabsLiquidityManager', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // // initialize
            // await sleep(60)
            // let contractInstance = await ethers.getContractAt("BrewlabsLiquidityManager", deployedAddress)
            // const res = await contractInstance.initialize(
            //     "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
            //     [
            //         "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
            //         "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7"
            //     ], // (brews-bnb) path
            //   )
            //   console.log('initialize BrewlabsLiquidityManager', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsLiquidityManager.sol:BrewlabsLiquidityManager",
                constructorArguments: [],
            })
        }

        if (config.brewsLocker) {
            Utils.infoMsg("Deploying BrewlabsLocker contract");

            let deployed = await deploy('BrewlabsLocker', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // // initialize
            // await sleep(60)
            // let contractInstance = await ethers.getContractAt("BrewlabsLocker", deployedAddress)
            // const _claimPerBlock = ethers.utils.parseUnits('1', 18) 
            // const res = await contractInstance.initialize(
            //     "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7", // _vestedToken (RARI)
            //     "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _earnedToken (BUSD)
            //   )
            // console.log('initialize BrewlabsLocker', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsLocker.sol:BrewlabsLocker",
                constructorArguments: [],
            })
        }

        if (config.vesting) {
            Utils.infoMsg("Deploying TokenVesting contract");

            let deployed = await deploy('TokenVesting', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // // initialize
            // await sleep(60)
            // let contractInstance = await ethers.getContractAt("TokenVesting", deployedAddress)
            // const _claimPerBlock = ethers.utils.parseUnits('1', 18) 
            // const res = await contractInstance.initialize(
            //     "0x856333816B8E934bCF4C08FAf00Dd46e5Ac0aaeC", // _vestedToken (RARI)
            //     "0x0000000000000000000000000000000000000000", // _earnedToken (BUSD)
            //     _claimPerBlock,                               // _claimPerBlock
            //   )
            // console.log('initialize TokenVesting', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/others/TokenVesting.sol:TokenVesting",
                constructorArguments: [],
            })
        }

        if (config.buffetLocker) {
            Utils.infoMsg("Deploying BUSDBuffetTeamLocker contract");

            let deployed = await deploy('BUSDBuffetTeamLocker', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BUSDBuffetTeamLocker", deployedAddress)
            const res = await contractInstance.initialize(
                "0x07335A076184C0453aE1987169D9c7ab7047a974", // _vestedToken (BUSD Buffet)
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _reflecteddToken (BUSD)
            )
            console.log('initialize BUSDBuffetTeamLocker', res)

            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/others/BUSDBuffetTeamLocker.sol:BUSDBuffetTeamLocker",
                constructorArguments: [],
            })
        }

        if (config.blvtVest) {
            Utils.infoMsg("Deploying BlocVaultVesting contract");

            let deployed = await deploy('BlocVaultVesting', {
                from: account,
                log: false
            });

            let deployedAddress = deployed.address;

            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BlocVaultVesting", deployedAddress)
            const res = await contractInstance.initialize(
                "0xb3ac46fE1A14589F5fB4EA735DA723cD12a3438A", // _vestedToken (BLVT)
                "0xb3ac46fE1A14589F5fB4EA735DA723cD12a3438A", // _reflecteddToken (BLVT)
            )
            console.log('initialize BlocVaultVesting', res)


            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/others/BlocVaultVesting.sol:BlocVaultVesting",
                constructorArguments: [],
            })
        }
    } catch (e) {
        console.log(e, e.stack)
    }

}

