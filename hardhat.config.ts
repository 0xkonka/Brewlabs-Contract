import "@nomiclabs/hardhat-waffle";

import "hardhat-deploy";
import "@nomiclabs/hardhat-ethers";
import "@openzeppelin/hardhat-upgrades";
import "@nomiclabs/hardhat-etherscan";
import "solidity-coverage";

const {
  infuraProjectId,
  accountPrivateKey,
  etherscanApiKey,
  alchemyApi,
  testMnemonics
} = require("./.secrets.js");

/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  paths: {
    sources: "./contracts",
  },
  defaultNetwork: "hardhat",
  // namedAccounts: {
  //   deployer: { default: 0 },
  //   alice: { default: 1 },
  //   bob: { default: 2 },
  //   rando: { default: 3 },
  // },

  networks: {
    hardhat: {
      accounts: {
        mnemonic: testMnemonics,
      },
      forking: {
        url: "https://bsc-dataseed.binance.org/",
        // blockNumber: 19376198,
      },
      // blockGasLimit: 12e6,

      // loggingEnabled: false,
      // mining: {
      //   auto: true,
      //   interval: [1000, 5000],
      // },

      allowUnlimitedContractSize: true,
    },

    kovan: {
      url: `https://kovan.infura.io/v3/${infuraProjectId}`,
      chainId: 42,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },

    ropsten: {
      url: `https://ropsten.infura.io/v3/${infuraProjectId}`,
      chainId: 3,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },

    rinkeby: {
      url: `https://rinkeby.infura.io/v3/${infuraProjectId}`,
      chainId: 4,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },

    eth_mainnet: {
      url: `https://mainnet.infura.io/v3/${infuraProjectId}`,
      chainId: 1,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },

    bsc_mainnet: {
      url: `https://bsc-dataseed.binance.org/`,
      chainId: 56,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },

    bsc_testnet: {
      url: `https://data-seed-prebsc-1-s1.binance.org:8545/`,
      chainId: 97,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },

    matic: {
      url: `https://polygon-rpc.com`,
      chainId: 137,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },
    fantom: {
      url: `https://rpc.ftm.tools/`,
      chainId: 250,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },
    avalanche: {
      url: `https://api.avax.network/ext/bc/C/rpc`,
      chainId: 43114,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },
    cronos: {
      url: `https://evm.cronos.org`,
      chainId: 25,
      //gasPrice: 20000000000,
      accounts: [`0x${accountPrivateKey}`],
    },
  },

  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: etherscanApiKey,
  },

  solidity: {
    compilers: [
      {
        version: "0.8.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
      {
        version: "0.7.4",
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
        },
      },
    ],
  },
  gasReporter: {
    enabled: true,
  },
};
