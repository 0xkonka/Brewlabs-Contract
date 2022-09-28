const path = require('path')
const Utils = require('../Utils');
const hre = require("hardhat")

const sleep = (delay) => new Promise((resolve) => setTimeout(resolve, delay * 1000));

module.exports = async ({getUnnamedAccounts, deployments, ethers, network}) => {

    try{
        const {deploy} = deployments;
        const accounts = await getUnnamedAccounts();
        let account = accounts[0];

        Utils.infoMsg(" ------------------------------------------------------------------------------- ")
        Utils.infoMsg(" --------------------------- Deploying Brewlabs Contracts ------------------- ")
        Utils.infoMsg(" ------------------------------------------------------------------------------- ")

        const config = {
            tokenFreezer: false,
            pairFreezer: false,

            farm: false,
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
            teamlocker: false,
            kodi: false,
            kodiTreasury: false,
            oracle: false,

            other: false,
        }

        if(config.other) {           
            Utils.infoMsg("Deploying BlocVestShareholderVault contract");

            let deployed = await deploy('BlocVestShareholderVault', {
                from: account,
                args: [],
                log:  false
            });
    
            let deployedAddress = deployed.address;    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            let contractInstance = await ethers.getContractAt("BlocVestShareholderVault", deployedAddress)
            let tx = await contractInstance.initialize(
                "0x592032513b329a0956b3f14d661119880F2361a6",
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                "0x10ed43c718714eb63d5aa57b78b54704e256024e",
                [
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x592032513b329a0956b3f14d661119880F2361a6"
                ],
                "0x1dD565b26FBc45e51Fa5aA360A918BA31B5aADd5"
            )
            await tx.wait()
          
            // verify
            await sleep(60);
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/others/BlocVestShareholderVault.sol:BlocVestShareholderVault",
                constructorArguments: [],
            }) 
        }

        if(config.oracle) {
            Utils.infoMsg("Deploying BrewlabsPriceOracle contract");
            let wbnb;
            switch(network.config.chainId) {
                case 97: 
                    wbnb = "0xae13d989dac2f0debff460ac112a837c89baa7cd" // bsc testnet
                    break;
                case 56: 
                    wbnb = "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c" // bsc mainnet
                    break;
                default: 
                Utils.errorMsg(`Not support ${network.config.chainId}`)
            }

            let deployed = await deploy('BrewlabsPriceOracle', {
                from: account,
                args: [wbnb],
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
    
            // initialize
            let contractInstance = await ethers.getContractAt("BrewlabsPriceOracle", deployedAddress)
            if(network.config.chainId === 56) {
                // set busd price
                await sleep(30)
                let tx = await contractInstance.setDirectPrice("0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", ethers.utils.parseUnits("1", 18));
                await tx.wait()
                // set bnb chainlink feed (bnb-usd)
                tx = await contractInstance.setAggregators([wbnb], ["0x0567f2323251f0aab15c8dfb1967e4e8a7d42aee"]) 
                await tx.wait()
                
                
                Utils.infoMsg("Deploying BrewlabsTwapOracle contract");
                let twapDeployed = await deploy('BrewlabsTwapOracle', {
                    from: account,
                    args: [
                        "0xF9B07b7528FEEb48811794361De37b4BAdE1734f", // pair
                        14400, // period
                        1663777859, // startTime
                    ],
                    log:  false
                });

                // verify
                await sleep(30)
                await hre.run("verify:verify", {
                    address: twapDeployed.address,
                    contract: "contracts/BrewlabsTwapOracle.sol:BrewlabsTwapOracle",
                    constructorArguments: [
                        "0xF9B07b7528FEEb48811794361De37b4BAdE1734f", // pair
                        14400, // period
                        1663777859, // startTime
                    ],
                }) 
            } else if(network.config.chainId === 97) {
                // set busd price
                await sleep(30)
                await contractInstance.setDirectPrice("0x2995bD504647b5EeE414A78be1d7b24f49f00FFE", ethers.utils.parseUnits("1", 18));
                // set bnb chainlink feed (bnb-usd)
                await sleep(30)
                await contractInstance.setAggregators([wbnb], ["0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526"]) 

                Utils.infoMsg("Deploying BrewlabsTwapOracle contract");
                let twapDeployed = await deploy('BrewlabsTwapOracle', {
                    from: account,
                    args: [
                        "0xB37d9c39d6A3873Dca3CBfA01D795a03f41b7298", // pair
                        14400, // period
                        1660708623, // startTime
                    ],
                    log:  false
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

        if(config.pairFreezer) {
            Utils.infoMsg("Deploying BrewlabsPairLocker implementation");
            let deployed = await deploy('BrewlabsPairLocker', 
                {
                    from: account,
                    args: [],
                    log:  false
                });
    
            let implementation = deployed.address;
            Utils.successMsg(`Implementation Address: ${implementation}`);

            Utils.infoMsg("Deploying BrewlabsPairFreezer contract");
            deployed = await deploy('BrewlabsPairFreezer', 
                {
                    from: account,
                    args: [implementation],
                    log:  false
                });
    
            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            if(network.config.chainId == 97) {
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

        if(config.tokenFreezer) {
            Utils.infoMsg("Deploying BrewlabsTokenLocker implementation");
            let deployed = await deploy('BrewlabsTokenLocker', 
                {
                    from: account,
                    args: [],
                    log:  false
                });
    
            let implementation = deployed.address;
            Utils.successMsg(`Implementation Address: ${implementation}`);

            Utils.infoMsg("Deploying BrewlabsTokenFreezer contract");
            deployed = await deploy('BrewlabsTokenFreezer', 
                {
                    from: account,
                    args: [implementation],
                    log:  false
                });
    
            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            
            if(network.config.chainId == 97) {
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

        if(config.treasury) {
            Utils.infoMsg("Deploying BrewlabsTreasury contract");
            let deployed = await deploy('BrewlabsTreasury', 
                {
                    from: account,
                    args: [],
                    log:  false
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

        if(config.kodiTreasury) {
            Utils.infoMsg("Deploying KODITreasury contract");
            let deployed = await deploy('KODITreasury', 
                {
                    from: account,
                    args: [],
                    log:  false
                });
    
            let deployedAddress = deployed.address;
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            await sleep(60)
            let contractInstance = await ethers.getContractAt("KODITreasury", deployedAddress)
            const res = await contractInstance.initialize(
                "0xbA5eAB68a7203C9FF72E07b708991F07f55eF40E", // _token (BREWS)
                "0x0000000000000000000000000000000000000000", // _dividendToken (BUSD)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0xbA5eAB68a7203C9FF72E07b708991F07f55eF40E",
                ]
              )
              console.log('initialize KODITreasury', res)
    
            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/KODITreasury.sol:KODITreasury",
                constructorArguments: [],
            })
        }

        if(config.farm) {
            Utils.infoMsg("Deploying BrewlabsFarm contract");
            const _hasDividend = false;
            const _rewardPerBlock = ethers.utils.parseUnits("0.951293759512937595", 18)
            let deployed = await deploy('BrewlabsFarm', 
                {
                    from: account,
                    args: [
                        "0xe5977835A013e3A5a52f44f8422734bd2dc545F0",
                        "0x0000000000000000000000000000000000000000",
                        _rewardPerBlock,
                        _hasDividend,
                    ],
                    log:  false
                });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsFarm", deployedAddress)
            await contractInstance.add(
                1000,                                                   // allocPoint
                "0x6b75970104032cE9720902Cea0A0E57Ce24a6077",           // lp token address
                0,                                                      // deposit fee
                0,                                                      // withdraw fee 
                365,                                                    // duration
                false
            )
    
            // verify
            // await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsFarm.sol:BrewlabsFarm",
                constructorArguments: [
                    "0xe5977835A013e3A5a52f44f8422734bd2dc545F0",
                    "0x0000000000000000000000000000000000000000",
                    _rewardPerBlock, 
                    _hasDividend,
                ],
            })
        }

        if(config.staking) {
            Utils.infoMsg("Deploying BrewlabsStaking contract");

            let deployed = await deploy('BrewlabsStaking', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsStaking", deployedAddress)
            const _hasDividend = false;
            const _rewardPerBlock = ethers.utils.parseUnits('0.713470319634703196', 18) 
            const res = await contractInstance.initialize(
                "0x6266a18F1605DA94e8317232ffa634C74646ac40", // _stakingToken (BTIv2)
                "0x6266a18F1605DA94e8317232ffa634C74646ac40", // _earnedToken (BTIv2)
                "0x0000000000000000000000000000000000000000", // _reflectionToken (BTCB)
                _rewardPerBlock,                              // _rewardPerBlock
                200,                                          // _depositFee (2%)
                0,                                          // _withdrawFee (0%)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
                [
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x6266a18F1605DA94e8317232ffa634C74646ac40",
                ], 
                _hasDividend,
                )

              console.log('initialize BrewlabsStaking', res)
    
            // verify
            // await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsStaking.sol:BrewlabsStaking",
                constructorArguments: [],
            })
        } 

        if(config.lockupStaking) {
            Utils.infoMsg("Deploying BrewlabsLockup contract");

            let deployed = await deploy('BrewlabsLockup', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
    
            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsLockup", deployedAddress)
            const res = await contractInstance.initialize(
                "0xe06f46AFD251B06152B478d8eE3aCea534063994", // _stakingToken 
                "0xe06f46AFD251B06152B478d8eE3aCea534063994", // _earnedToken 
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _reflectionToken 
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
                [
                    "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56",
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0xe06f46AFD251B06152B478d8eE3aCea534063994"
                ],
                "0x6Aa5F8B4cC8cdF5284C47FB3C02EE49F2C77679B", // whitelist contract                                                 
            )
            console.log('initialize BrewlabsLockup', res)
            
            let _rate = ethers.utils.parseUnits('1342275.494672754946727549', 18)
            await contractInstance.addLockup(30, 0, 10, _rate, 0) // _duration, _depositFee, _withdrawFee, _rate, _totalStakedLimit

            // verify
            // await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsLockup.sol:BrewlabsLockup",
                constructorArguments: [],
            })
        }

        if(config.lockupStakingV2) {
            Utils.infoMsg("Deploying BrewlabsLockupV2 contract");

            let deployed = await deploy('BrewlabsLockupV2', {
                from: account,
                log:  false
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
                contract: "contracts/BrewlabsLockupV2.sol:BrewlabsLockupV2",
                constructorArguments: [],
            })
        }

        if(config.lockupFixed) {
            Utils.infoMsg("Deploying BrewlabsLockupFixed contract");

            let deployed = await deploy('BrewlabsLockupFixed', {
                from: account,
                log:  false
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
                contract: "contracts/BrewlabsLockupFixed.sol:BrewlabsLockupFixed",
                constructorArguments: [],
            })
            
        }
        
        if(config.kodi) {
            Utils.infoMsg("Deploying BrewlabsStaking(KODI) contract");

            let deployed = await deploy('BrewlabsStakingClaim', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsStakingClaim", deployedAddress)
            const _rewardPerBlock = ethers.utils.parseUnits("1157.407407407", 18) 
            const res = await contractInstance.initialize(
                "0x7f4f3bc4a5634454398580b9112b7e493e2129fa", // _stakingToken (KODI)
                "0x7f4f3bc4a5634454398580b9112b7e493e2129fa", // _earnedToken (KODI)
                "0x0000000000000000000000000000000000000000", // _earnedToken (BNB)
                _rewardPerBlock,                              // _rewardPerBlock
                0,                                          // _depositFee (0%)
                0,                                          // _withdrawFee (0%)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
                [
                  "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                  "0x7f4f3bc4a5634454398580b9112b7e493e2129fa"
                ],                                            // WBNB-KODI path           
              )
              console.log('initialize BrewlabsStaking(KODI)', res)
    
            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsStakingClaim.sol:BrewlabsStakingClaim",
                constructorArguments: [],
            })
        } 
        
        if(config.multi) {
            Utils.infoMsg("Deploying BrewlabsStakingMulti(SeTC) contract");

            let deployed = await deploy('BrewlabsStakingMulti', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
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
                contract: "contracts/BrewlabsStakingMulti.sol:BrewlabsStakingMulti",
                constructorArguments: [],
            })
        }

        if(config.multiLockup) {
            Utils.infoMsg("Deploying BrewlabsLockupMulti contract");

            let deployed = await deploy('BrewlabsLockupMulti', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);
    
            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsLockupMulti", deployedAddress)
            const _rewardPerBlock = ethers.utils.parseUnits('1157.407407407', 18)
            const res = await contractInstance.initialize(
                "0xc50F00779559b2E13Dee314530cC387CC5dD85ae", // _stakingToken
                "0xc50F00779559b2E13Dee314530cC387CC5dD85ae", // _earnedToken
                [
                    "0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c",
                    "0x2170Ed0880ac9A755fd29B2688956BD959F933F8",
                    "0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402",
                    "0xCC42724C6683B7E57334c4E856f4c9965ED682bD",
                    "0x1CE0c2827e2eF14D5C4f29a091d735A204794041",
                ], // _reflectionToken 
                _rewardPerBlock,                              // reward per block
                0,                                            // deposit fee
                50,                                           // withdraw fee
                14,                                           // lock duration (days)
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [],
            )
            console.log('initialize BrewlabsLockupMulti', res)
    
            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsLockupMulti.sol:BrewlabsLockupMulti",
                constructorArguments: [],
            })
        }
        
        if(config.liquidityMgr) {
            Utils.infoMsg("Deploying BrewlabsLiquidityManager contract");

            let deployed = await deploy('BrewlabsLiquidityManager', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("BrewlabsLiquidityManager", deployedAddress)
            const res = await contractInstance.initialize(
                "0x10ed43c718714eb63d5aa57b78b54704e256024e", // pancake router v2
                [
                    "0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c",
                    "0x6aAc56305825f712Fd44599E59f2EdE51d42C3e7"
                ], // (brews-bnb) path
              )
              console.log('initialize BrewlabsLiquidityManager', res)
    
            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/BrewlabsLiquidityManager.sol:BrewlabsLiquidityManager",
                constructorArguments: [],
            })
        } 

        if(config.brewsLocker) {
            Utils.infoMsg("Deploying BrewlabsLocker contract");

            let deployed = await deploy('BrewlabsLocker', {
                from: account,
                log:  false
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
        
        if(config.vesting) {
            Utils.infoMsg("Deploying TokenVesting contract");

            let deployed = await deploy('TokenVesting', {
                from: account,
                log:  false
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

        if(config.buffetLocker) {
            Utils.infoMsg("Deploying BUSDBuffetTeamLocker contract");

            let deployed = await deploy('BUSDBuffetTeamLocker', {
                from: account,
                log:  false
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

        if(config.teamlocker) {
            Utils.infoMsg("Deploying TeamLocker contract");

            let deployed = await deploy('TeamLocker', {
                from: account,
                log:  false
            });
    
            let deployedAddress = deployed.address;
    
            Utils.successMsg(`Contract Address: ${deployedAddress}`);

            // initialize
            await sleep(60)
            let contractInstance = await ethers.getContractAt("TeamLocker", deployedAddress)
            const res = await contractInstance.initialize(
                "0x07335A076184C0453aE1987169D9c7ab7047a974", // _vestedToken (BUSD Buffet)
                "0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56", // _reflecteddToken (BUSD)
              )
            console.log('initialize TeamLocker', res)
    
            // verify
            await sleep(60)
            await hre.run("verify:verify", {
                address: deployedAddress,
                contract: "contracts/others/TeamLocker.sol:TeamLocker",
                constructorArguments: [],
            })
        }

        if(config.blvtVest) {
            Utils.infoMsg("Deploying BlocVaultVesting contract");

            let deployed = await deploy('BlocVaultVesting', {
                from: account,
                log:  false
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
    } catch (e){
        console.log(e,e.stack)
    }

}

