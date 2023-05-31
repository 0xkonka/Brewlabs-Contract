# Brewlabs Contracts
This repository includes all smart contracts for Brewlabs products.

## Architecture
```ml
airdrop
├─ BrewlabsAirdrop           — "Airdrop contract for Brewlabs Airdrop Tool"
├─ BrewlabsAirdropNft        — "NFT Airdrop contract for Brewlabs Airdrop Tool"
farm
├─ BrewlabsFarm              — "Normal farm contract"
├─ BrewlabsFarmFactory       — "Factory for farm auto deployment"
├─ BrewlabsFarmImpl          — "Farm implementation for farm factory"
indexes
├─ BrewlabsIndexFactory      — "Factory contract for Brewlabs Index"
├─ BrewlabsIndex             — "Brewlabs Index logic implementation"
├─ BrewlabsIndexNft          — "NFT that holds index tokens"
├─ BrewlabsDeployNft         — "NFT that holds commission of Brewlabs Index"
├─ BrewlabsFlaskNft          — "Brewlabs NFT series"
├─ BrewlabsNftDiscountMgr    — "NFT discount manager"
libs
├─ ...                       — "Libraries that are used in contracts"
mocks
├─ ...                       — "Mock contracts for unit test"
others
├─ ...                       — "Includes contracts for external services"
pool
├─ BrewlabsStaking           — "Normal single staking"
├─ BrewlabsLockup            — "Normal lockup staking pool"
├─ BrewlabsLockupPenalty     — "Lockup staking pool with penalty fee"
├─ BrewlabsLockupFee         — "Lockup staking pool with fee"
├─ BrewlabsLockupFixed       — "Lockup staking pool with fixed reward rate"
├─ BrewlabsLockupMulti       — "Lockup staking pool for token with multiple reflections"
├─ BrewlabsPoolFactory       — "Factory that can deploy single staking or lockup staking automatically"
├─ BrewlabsStakingImpl       — "Single staking implementation"
├─ BrewlabsLockupImpl        — "Lockup staking implementation"
├─ BrewlabsLockupPenaltyImpl — "Lockup penalty implementation"
BrewlabsConfig               — "Farm, Pool registrerar"
BrewlabsLiquidity            — "Liquidity manager. Users can add/remove liquidity via a contract"
...
```

## Development

### Setup
1. Clone project and install node modules.

```sh
git clone https://github.com/brainstormk/brewlabs-staking-contracts.git
yarn install
```

2. Install forge
You will need the Rust compiler and Cargo, the Rust package manager. The easiest way to install both is with [**Rust Compiler**](https://rustup.rs/). On Windows, you will also need a recent version of Visual Studio, installed with the "Desktop Development With C++" Workloads option.

```sh
cargo install --git https://github.com/foundry-rs/foundry --profile local --force foundry-cli anvil chisel
forge install
```

### Build

```sh
yarn clean
yarn compile
yarn build
```

### Run tests

```sh
forge test
forge test --match-contract BrewlabsIndex -vvv
```

### Contract deployment
