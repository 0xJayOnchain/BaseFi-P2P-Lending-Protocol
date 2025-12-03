## P2P Lending Protocol

This is a P2P Lending Protocol built with the BASE ecosystem in mind.

## Goals
- [x] Build out a functioning P2P protocol <!-- In Progress -->
- [x] Create functioning test suite for full protocol <!-- In Progress -->
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

Tests added
- `PriceOracle.t.sol` — validates normalization and aggregator plumbing.
- `LendingPoolOfferRequest.t.sol` — offer/request escrow create & cancel flows.
- `PoolAdapter.t.sol` — demonstrates contract-based lenders and MINTER_ROLE grant.
- `Matching.t.sol` — matching, loan creation and repay flows (NFT mint/burn).
- `ClaimFees.t.sol` — owner fee accrual and claiming tests (single & multi-token).
 - `Liquidation.t.sol` — liquidation on expiry and undercollateralization using the oracle.
 - `OwnerSweepSwap.t.sol` — owner-only sweep-and-swap of fees via Uniswap V2-style router.

Notes
- Owner-only admin calls exist in `LendingPool` (set fees, set NFT contract, claim owner fees). Tests instantiate the pool with the test contract as owner to exercise these functions.
- Many tests use `MockERC20` and `MockAggregator` found in `src/mocks/`.
 - An optional hybrid path is planned: owner sweep-and-swap is implemented; user-opt-in repay/liquidate with conversion can be added with slippage controls and router whitelisting.

Next recommended steps
- Implement `liquidate(loanId)` and write expiry/undercollateralized tests.
- Add additional edge-case tests for ERC20 tokens that do not return bools, and for tokens with different decimals.
 - Add optional repay/liquidate variants with conversion and a router whitelist; consider pausability for swap paths.

