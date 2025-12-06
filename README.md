## P2P Lending Protocol

This is a P2P Lending Protocol built to make lending easier.

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

Contracts live in `src/` and tests live in `test/` (Foundry). The project uses OpenZeppelin contracts located in `lib/openzeppelin-contracts` and `lib/forge-std` for testing helpers. Environment configs live in `config/`.

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
 - Opt-in swap repay: Borrowers can use `repayFullWithSwap(...)` to swap from any input token into the loan’s lend token via a whitelisted router and repay in one tx. See "Opt-in swap paths" below for rules and constraints.
 - Opt-in swap liquidation: Lenders/NFT owners can use `liquidateWithSwap(...)` to convert arbitrary collateral or proceeds into the lend token via a whitelisted router during liquidation. See "Opt-in swap paths" below for rules and constraints.

Compatibility
- Fee-on-transfer tokens: currently unsupported. We require escrow transfers to credit the exact requested amount; fee-on-transfer tokens would result in under-escrow and are rejected with `fee-on-transfer unsupported`.
- Non-standard ERC20s: we use SafeERC20 for compatibility, and tests include non-standard behaviors and unusual decimals.

Opt-in swap paths (Repay and Liquidate with swap)
- What: `repayFullWithSwap(uint256 loanId, address router, uint256 amountIn, address[] path, uint256 amountOutMin, uint256 deadline)` lets the borrower repay using an arbitrary input token.
- What (liquidation): `liquidateWithSwap(uint256 loanId, address router, address[] path, uint256 amountOutMin, uint256 deadline)` lets the lender/NFT owner liquidate and convert via a whitelisted router in one tx.
- Router whitelist: `router` must be whitelisted by the owner using `setRouterWhitelisted(address,bool)`.
- Path rules: `path.length >= 2`; `path[0]` is the input token provided by the borrower; `path[path.length - 1]` MUST equal the loan’s `lendToken`.
- Path rules (liquidation): `path.length >= 2`; `path[path.length - 1]` MUST equal the loan’s `lendToken`. Middle hops are allowed; inputs must be available to the pool during liquidation.
- Slippage & deadline: borrower sets `amountOutMin` and `deadline`. The router enforces the deadline; the pool requires swap output `>= totalDue` (principal + accrued interest).
- Slippage & deadline (liquidation): caller sets `amountOutMin` and `deadline`. The pool requires swap output to cover outstanding due; excess handling follows existing liquidation rules.
- Pausable & permissions: function is `whenNotPaused`; only the `borrower` can call it.
- Pausable & permissions (liquidation): function is `whenNotPaused`; only the lender/NFT owner may call it.
- Approvals: allowance for the router is increased only for the swap and then reset to zero.
- Events: emits `RepayWithSwap(loanId, router, tokenIn, amountIn, amountOut)` on success for observability.
- Events (liquidation): emits `LoanLiquidatedWithSwap(loanId, router, amountOut)` after successful liquidation and conversion.

Batch owner fee claims
- What: `claimOwnerFeesBatch(address[] tokens)` claims accrued owner fees across multiple tokens in one call. Non-zero claims emit the existing per-token `OwnerFeesClaimed` events.
- Summary event: additionally emits `OwnerFeesClaimedBatch(address to, address[] tokens, uint256[] amounts)` summarizing all processed tokens and amounts (zero amounts indicate skipped tokens with no fees).
- Safety: empty token lists revert; zero-fee tokens are skipped without reverting.

Next recommended steps (Round 2 scope)
- Eventing and observability: emit events for pause/unpause, router whitelist changes, collateral validation toggles, and oracle feed updates.
- More edge-case tests: fee-on-transfer tokens, tokens with unusual decimals, non-standard ERC20s.
- Gas and safety reviews: add CI (Slither, solhint), audit prep checklist.
- Optional repay/liquidate with conversion: user-opt-in paths with slippage controls and router whitelist.

CI & static analysis
- GitHub Actions runs Foundry tests, Slither static analysis, and solhint style/lint checks. See `.github/workflows/ci.yml`.

Security & audit prep
- See `SECURITY.md` for threat model, invariants, safety checks, and an audit checklist.
 - See `docs/architecture.md` for Mermaid diagrams of the architecture and key sequences (offer/request, match, repay, repayWithSwap, liquidate, liquidateWithSwap, batch fee claims).
 - See `docs/governance.md` for governance, admin controls, and emergency procedures.
 - See `docs/deployment.md` for environment-specific configuration and deployment checklist.
 - See `docs/subgraph/` for a starter subgraph (schema, mappings, manifest) to index protocol events.
 - See `docs/metrics.md` for a metrics catalog and frontend-friendly indexing notes.
 - See `docs/integrations.md` for router/aggregator adapters, wallet/dApp integration guidance, and an SDK outline.

