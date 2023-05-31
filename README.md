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
├─ BrewlabsDeployNft         — "NFT that holds commission of Brewlabs Index"
├─ BrewlabsFlaskNft          — "Brewlabs NFT series"
├─ BrewlabsIndex             — "Brewlabs Index logic implementation"
├─ BrewlabsIndexFactory      — "Factory contract for Brewlabs Index"
├─ BrewlabsIndexNft          — "NFT that holds index tokens"
├─ BrewlabsNftDiscountMgr    — "NFT discount manager"
libs
├─ ...                       — "Libraries that are used in contracts"
mocks
├─ ...                       — "Mock contracts for unit test"
others
├─ ...                       — "Includes contracts for external services"
pool
├─ BrewlabsLockup            — "Normal lockup staking pool"
├─ BrewlabsLockupFee         — "Lockup staking pool with fee"
├─ BrewlabsLockupFixed       — "Lockup staking pool with fixed reward rate"
├─ BrewlabsLockupMulti       — "Lockup staking pool for token with multiple reflections"
├─ BrewlabsLockupPenalty     — "Lockup staking pool with penalty fee"
├─ BrewlabsStaking           — "Normal staking pool"
├─ BrewlabsPoolFactory       — "Factory contract that can deploy single staking or lockup staking automatically"
├─ BrewlabsStakingImpl       — "Single staking implementation"
├─ BrewlabsLockupImpl        — "Lockup staking implementation"
├─ BrewlabsLockupPenaltyImpl — "Lockup penalty implementation"
BrewlabsConfig               — "Farm, Pool registrerar"
BrewlabsLiquidity            — "Liquidity manager. Users can add/remove liquidity via a contract"
...
```

## Development

### Setup

### Build

### Run tests

### Contract deployment
