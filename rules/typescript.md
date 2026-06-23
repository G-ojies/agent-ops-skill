# TypeScript Rules — Agent Code

Auto-loading coding rules for TypeScript agent implementations. These encode the agent-ops non-negotiables at the code level.

## SDK & types
- Default to `@solana/kit` (web3.js v2). Only import `@solana/web3.js` v1 behind an interop boundary a dependency forces.
- Use `bigint` for lamports and token amounts. Never `number` for money — precision loss is a real bug.
- All transactions are `version: 0`.

## Transaction safety (enforced, not optional)
- **Simulate before the first send.** A send path with no upstream simulation is a bug.
- **Never re-sign on retry.** Derive the signature once; rebroadcast the same bytes. If a retry path calls a signing function, that's a defect — flag it.
- Capture `{ blockhash, lastValidBlockHeight }` together; confirm by blockheight, never `setTimeout`-as-confirmation.
- Priority fees via `@solana-program/compute-budget`, capped, non-zero on mainnet.

## Guardrails & secrets
- Every action passes a `guard()` (allowlist + caps) before any send.
- Secrets only from `process.env` / secret manager, read once. Never log raw objects that may carry key material — redact at the boundary.
- Dry-run is the default; live sends gated behind an explicit flag.

## Errors & retries
- Classify errors (retryable vs terminal). Backoff with jitter; honor `Retry-After`.
- Two-strike rule: same failure twice → stop and surface, don't loop.
- No empty `catch`. Either handle, classify-and-rethrow, or journal-and-fail.

## Style
- `async/await`, no floating promises (`await` or explicitly `void`).
- Pure DECIDE function — no I/O inside decision logic, so it stays unit-testable.
- Prefer explicit return types on exported functions.
