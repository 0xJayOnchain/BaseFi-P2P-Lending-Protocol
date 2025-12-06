# Security & Audit Prep

This document summarizes the protocol’s threat model, assumptions, invariants, and an audit checklist to guide reviews.

Last updated: 2025-12-06

## Scope

Contracts under review (non-exhaustive):
- `src/LendingPool.sol` — core protocol: offers/requests escrow, loan matching, interest, fees, repay, liquidation, opt-in swap paths, batching.
- `src/PriceOracle.sol` — registry of price feeds and staleness guard.
- `src/LoanPositionNFT.sol` — positions as ERC-721 (mint/burn controlled by role).
- `src/BaseP2P.sol` — safe transfer helpers and shared utilities.
- `src/mocks/*` — testing-only; excluded from production scope.

Dependencies:
- OpenZeppelin libraries (Ownable, Pausable, ReentrancyGuard, ERC20/721, SafeERC20).
- Foundry test suite.

## Assumptions & Limitations

- ERC20 transfers must be standard (no fee-on-transfer). Escrow requires exact amounts; fee-on-transfer tokens may cause under-escrow and are rejected.
- SafeERC20 is used for token interactions; non-standard return values are handled but not guaranteed for all edge tokens.
- Price feeds must be configured per asset. Loans referencing tokens without a feed may be restricted by collateral validation settings.
- Oracle staleness guard (`maxPriceAge`) is configurable; stale prices must revert when validation is enforced.
- Router whitelist enforces only explicitly allowed routers for swaps. Business logic assumes routers perform as expected with provided path/deadline/amounts.
- Pausable pattern is used to halt critical flows during incidents.
- Access control relies on owner-only functions and specific role checks (e.g., NFT minter).

## Threat Model

Primary assets:
- Escrowed ERC20s (lend/collateral tokens).
- Loan position NFTs representing borrower/lender state.
- Owner fee accrual balances.

Adversaries:
- Malicious borrowers/lenders attempting to drain escrow, bypass repayment/liquidation rules, or manipulate interest/fees.
- External attacker exploiting reentrancy, allowance mismanagement, or unsafe approvals.
- Oracle manipulator providing stale or incorrect prices if feeds are misconfigured.
- Router-level attacker exploiting swap path assumptions or deadline/slippage handling.

Attack surfaces:
- Offer/request creation and cancellation.
- Matching, interest accrual, and repayment flows.
- Liquidation flows and opt-in swap pathways.
- Owner fee claim (single and batch) and sweep/swap.
- Admin setters (fees, whitelist, validation toggles, NFT address).

## Invariants (to be maintained)

Escrow & accounting:
- Escrowed amounts match declared offers/requests; no under-crediting or silent skimming.
- Interest accrual is monotonic, based on agreed parameters; total due calculation is consistent across flows.
- Repayment reduces principal and interest exactly once; double-spend prevented.
- Owner fees accrue from configured sources only; claiming decreases internal balances accordingly.

Permissions & roles:
- Only owner can set admin parameters (fees, whitelist, NFT, validation toggles, oracle age).
- Borrower-only actions: loan repayment, including `repayFullWithSwap`.
- Lender/NFT-owner-only actions: liquidation, including `liquidateWithSwap`.
- Pausable functions revert when paused.
 - Guardian role (optional): guardian can pause; only owner can unpause.

Oracle & pricing:
- When collateral validation is enabled, price data must be available and not stale.
- Matching and liquidation guard against undercollateralization when validation is enabled.

Swaps & approvals:
- Router must be whitelisted for any swap-based flow.
- Swap paths must terminate in the loan’s lend token; minimum output and deadline enforced.
- Temporary allowances are set only for the duration of swaps and reset to zero immediately after.
- No lingering approvals that can be abused post-transaction.

Events & observability:
- Critical actions emit events: pause/unpause, whitelist changes, collateral validation toggles, price age changes, repay/liquidate with swap, owner fee claims (including batch summary).
 - Lifecycle events: `LoanMatched` on creation and `LoanClosed` on closure (repaid/liquidated) for frontend-friendly indexing.

## Safety Checks (Design & Code)

- Use `ReentrancyGuard` on state-mutating external functions that transfer tokens.
- Always use `SafeERC20` for transfers/approvals; clear allowances back to 0 after swaps.
- Validate inputs: non-empty token lists for batch operations, valid `loanId`, role ownership checks.
- Enforce `whenNotPaused` on key flows (offer/request, match, repay, liquidate, swap paths).
- Validate router whitelist before swap-based flows.
- Validate swap paths (`path.length >= 2`, ends with `lendToken`), slippage (`amountOutMin`), and `deadline`.
- Validate oracle staleness when collateral validation is enabled.
- Avoid “stack too deep” refactors that obscure safety; keep minimal locals and clear control flow.
- Prefer internal helpers for shared logic to reduce divergence and audit surface.

## Testing & Verification Checklist

Unit tests
- Offers/requests: create, cancel, escrow correctness.
- Matching & loans: interest accrual, repay, and NFT lifecycle.
- Repay with swap: borrower-only, whitelist, path rules, slippage/deadline, paused.
- Liquidate with swap: lender-only, whitelist, path rules, paused, oracle-fed setup.
- Owner fee claims: single, batch, zero-fee skips, empty-list revert, summary event.
- Pausable: all core flows revert when paused.
- Router whitelist: enforced for swap flows (owner sweep, repay, liquidation).
- Collateral validation: opt-in behavior and staleness guard.

Static analysis & lint
- Slither: run and triage findings; justify or fix high/medium findings.
- Solhint: style and NatSpec compliance; single-contract-per-file rule in tests.
- Gas profiling (optional): identify hotspots in matching/repay/liquidation.

Formal/advanced (optional)
- Invariant testing: escrow balance never negative; total due monotonic; event emissions.
- Differential testing on swap amounts with mocks.

## Incident Response & Pausing

- Pausable owner can halt critical operations during incidents.
- Document the pause scope (which functions) and unpause procedure.
- Consider multi-sig for ownership in production deployments.

## Deployment & Configuration

- Set router whitelist to known, vetted routers only.
- Configure `PriceOracle` feeds and `maxPriceAge` appropriately per token.
- Set `LoanPositionNFT` address and roles before enabling public flows.
- Review fee settings and accrual destinations.
 - Configure `liquidationGracePeriodSecs` (optional) to delay expiry-based liquidation.
 - Configure interest rate band (min/max BPS) if desired to constrain offers/requests.

## Known Risks & Mitigations

- Fee-on-transfer ERC20s: unsupported; mitigate by explicit reverts and documentation.
- Oracle dependency: staleness and correctness; mitigate via max age guard and feed management.
- Swap reliance: path correctness and slippage; mitigate via whitelist, input validation, and approval hygiene.
- Ownership centralization: risk of misconfiguration; mitigate via multi-sig and change control.
 - Concentration risk: mitigate by enforcing per-asset caps, per-user caps, and a global active principal cap.
 - Pathological terms: mitigate by enforcing interest rate bands and a maximum loan duration.

## Audit Handover

Provide to auditors:
- Commit hash and branch (`development`).
- Build tooling versions (Foundry, Solidity compiler).
- Test coverage report and Slither/solhint outputs.
- This SECURITY.md and any architectural diagrams.
- List of intended chains and token standards.
