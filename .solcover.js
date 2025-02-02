module.exports = {
  skipFiles: [
    "./BrewlabsFarm.sol",
    "./BrewlabsLiquidityManager.sol",
    "./BrewlabsLocker.sol",
    "./BrewlabsLockup.sol",
    "./BrewlabsLockupFee.sol",
    "./BrewlabsLockupFixed.sol",
    "./BrewlabsLockupMulti.sol",
    "./BrewlabsLockupV2.sol",
    "./BrewlabsPairFreezer.sol",
    "./BrewlabsPairLocker.sol",
    "./BrewlabsPriceMulticall.sol",
    "./BrewlabsPriceOracle.sol",
    "./BrewlabsRevenue.sol",
    "./BrewlabsStaking.sol",
    "./BrewlabsStakingClaim.sol",
    "./BrewlabsStakingMulti.sol",
    "./BrewlabsTokenConstructor.sol",
    "./BrewlabsTokenFreezer.sol",
    "./BrewlabsTokenLocker.sol",
    "./BrewlabsTreasury.sol",
    "./libs/BokkyPooBahsDateTimeLibrary.sol",
    "./libs/IBrewlabsFreezer.sol",
    "./libs/IBrewlabsPairLocker.sol",
    "./libs/IBrewlabsTokenLocker.sol",
    "./libs/IPriceOracle.sol",
    "./libs/IUniFactory.sol",
    "./libs/IUniPair.sol",
    "./libs/IUniRouter01.sol",
    "./libs/IUniRouter02.sol",
    "./libs/IWETH.sol",
    "./libs/PriceOracle.sol",
    "./mock/MockToken.sol",
    "./others/BaltoTeamLocker.sol",
    "./others/BaltoTreasury.sol",
    "./others/BGLTreasury.sol",
    "./others/BlocVaultVesting.sol",
    "./others/BlocVestAccumulatorVault.sol",
    "./others/BlocVestShareholderVault.sol",
    "./others/BlocVestTreasury.sol",
    "./others/BUSDBuffetTeamLocker.sol",
    "./others/DiversFiTeamLocker.sol",
    "./others/JigsawDistributor.sol",
    "./others/OgemTreasury.sol",
    "./others/RentEezTreasury.sol",
    "./others/ShitfaceInuTeamLocker.sol",
    "./others/TeamLocker.sol",
    "./others/TestDateTime.sol",
    "./others/TokenVesting.sol",
    "./others/VulkaniaTreasury.sol",
    "./others/WanchorTeamLocker.sol",
  ],
  // configureYulOptimizer: true,
  // solcOptimizerDetails: {
  //   peephole: false,
  //   jumpdestRemover: false,
  //   orderLiterals: true, // <-- TRUE! Stack too deep when false
  //   deduplicate: false,
  //   cse: false,
  //   constantOptimizer: false,
  //   yul: false,
  // },
};
