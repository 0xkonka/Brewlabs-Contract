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

    goerli: {
      url: `https://goerli.infura.io/v3/${infuraProjectId}`,
      chainId: 5,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["mainnet"]],
    },

    eth_mainnet: {
      url: `https://mainnet.infura.io/v3/${infuraProjectId}`,
      chainId: 1,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["mainnet"]],
    },

    bsc_mainnet: {
      url: `https://bsc-dataseed.binance.org/`,
      chainId: 56,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["bsc"]],
    },

    bsc_testnet: {
      url: `https://data-seed-prebsc-2-s1.binance.org:8545/`,
      chainId: 97,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["bsc"]],
    },

    matic: {
      url: `https://polygon-rpc.com`,
      chainId: 137,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["bsc"]],
    },
    fantom: {
      url: `https://rpc.ftm.tools/`,
      chainId: 250,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["bsc"]],
    },
    avalanche: {
      url: `https://api.avax.network/ext/bc/C/rpc`,
      chainId: 43114,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["bsc"]],
    },
    cronos: {
      url: `https://evm.cronos.org`,
      chainId: 25,
      //gasPrice: 20000000000,
      accounts: [accountPrivateKey["bsc"]],
    },
    frenchain: {
      chainId: 44444,
      url: 'https://rpc-02.frenscan.io/',
      accounts: [accountPrivateKey["bsc"]],
      gasPrice: 3000000000
    }
  },

  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: etherscanApiKey,
    customChains: [  // custom config for blockscout explorer
      {
        network: "frenchain",
        chainId: 44444,
        urls: {
          apiURL: "https://frenscan.io/api",
          browserURL: "https://frenscan.io/"
        }
      }
    ]
  },

  solidity: {
    compilers: [
      {
        version: "0.8.14",
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
    ],
  },
  gasReporter: {
    enabled: true,
  },
};
