## P2P Lending Protocol

This is a P2P Lending Protocol built with the BASE ecosystem in mind.

## Goals
- [x] Build out a functioning P2P protocol <!-- In Progress -->
- [x] Create functioning test suite for full protocol <!-- In Progress -->
- [x] Round 1 safety features: pausability, router whitelist, opt-in collateral validation, oracle staleness guard
- [ ] Code/Security Audit <!-- Not yet started -->
- [ ] Launch product <!-- Not yet started -->

## Quickstart (developer)

Prerequisites: Foundry (forge), a modern Solidity toolchain. From the repo root:

```bash
# run tests
forge test -vv

# build
forge build
```

Contracts live in `src/` and tests live in `test/` (Foundry). The project uses OpenZeppelin contracts located in `lib/openzeppelin-contracts` and `lib/forge-std` for testing helpers.

Key contracts
- `PriceOracle.sol` — registry of chainlink-like aggregators and normalizes prices to 1e18.
- `BaseP2P.sol` — safe ERC20 transfer helpers used by the pool.
- `LendingPool.sol` — core protocol: offers/requests escrow, loan matching, NFT positions, interest, repay, owner fees, penalty handling.
- `LoanPositionNFT.sol` — ERC721 representing lender/borrower positions (mint/burn controlled by MINTER_ROLE).
 - `MockUniswapV2Router.sol` — testing-only router used to verify owner sweep-and-swap.
 - `mocks/MockAggregator.sol` — chainlink-like feed mock with controllable `updatedAt` to test staleness.

Tests added
- `PriceOracle.t.sol` — validates normalization and aggregator plumbing.
- `LendingPoolOfferRequest.t.sol` — offer/request escrow create & cancel flows.
- `PoolAdapter.t.sol` — demonstrates contract-based lenders and MINTER_ROLE grant.
- `Matching.t.sol` — matching, loan creation and repay flows (NFT mint/burn).
- `ClaimFees.t.sol` — owner fee accrual and claiming tests (single & multi-token).
 - `Liquidation.t.sol` — liquidation on expiry and undercollateralization using the oracle.
 - `OwnerSweepSwap.t.sol` — owner-only sweep-and-swap of fees via Uniswap V2-style router.
 - `Pausable.t.sol` — verifies that core flows revert when paused, including cancel functions.
 - `RouterWhitelist.t.sol` — enforces router whitelist for owner sweep-and-swap.
 - `CollateralValidation.t.sol` — opt-in collateral checks at match using oracle pricing.
 - `PriceOracleStaleness.t.sol` — staleness guard behavior when `maxPriceAge` is configured.

Notes
- Owner-only admin calls exist in `LendingPool` (set fees, set NFT contract, claim owner fees). Tests instantiate the pool with the test contract as owner to exercise these functions.
- Many tests use `MockERC20` and `MockAggregator` found in `src/mocks/`.
 - Safety: `LendingPool` is `Pausable`; router whitelist is enforced for swaps; collateral validation is opt-in via `setEnforceCollateralValidation(bool)`; `PriceOracle` supports `maxPriceAge` staleness checks.
 - An optional hybrid path is planned: owner sweep-and-swap is implemented; user-opt-in repay/liquidate with conversion can be added with slippage controls and router whitelisting.

Next recommended steps (Round 2 scope)
- Eventing and observability: emit events for pause/unpause, router whitelist changes, collateral validation toggles, and oracle feed updates.
- More edge-case tests: fee-on-transfer tokens, tokens with unusual decimals, non-standard ERC20s.
- Gas and safety reviews: add CI (Slither, solhint), audit prep checklist.
- Optional repay/liquidate with conversion: user-opt-in paths with slippage controls and router whitelist.

