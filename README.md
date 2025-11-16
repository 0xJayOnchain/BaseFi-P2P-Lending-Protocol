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

Tests added
- `PriceOracle.t.sol` — validates normalization and aggregator plumbing.
- `LendingPoolOfferRequest.t.sol` — offer/request escrow create & cancel flows.
- `PoolAdapter.t.sol` — demonstrates contract-based lenders and MINTER_ROLE grant.
- `Matching.t.sol` — matching, loan creation and repay flows (NFT mint/burn).
- `ClaimFees.t.sol` — owner fee accrual and claiming tests (single & multi-token).

Notes
- Owner-only admin calls exist in `LendingPool` (set fees, set NFT contract, claim owner fees). Tests instantiate the pool with the test contract as owner to exercise these functions.
- Many tests use `MockERC20` and `MockAggregator` found in `src/mocks/`.

Next recommended steps
- Implement `liquidate(loanId)` and write expiry/undercollateralized tests.
- Add additional edge-case tests for ERC20 tokens that do not return bools, and for tokens with different decimals.

