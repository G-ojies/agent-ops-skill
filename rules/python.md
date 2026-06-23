# Python Rules — Agent Code

Auto-loading coding rules for Python agent implementations (`solana-py` + `solders`). The agent-ops non-negotiables apply identically to Python — only the API names differ.

## SDK & types
- `solana-py` (`AsyncClient`) for RPC, `solders` for keypairs/transactions/primitives.
- Use `int` lamports; for token UI math use `Decimal`, never `float` for money.
- Prefer the async client for the loop; don't block the event loop with sync calls.

## Transaction safety (enforced, not optional)
- **Simulate before the first send** (`simulate_transaction`); a non-null err blocks the send.
- **Never re-sign on retry.** Sign once, rebroadcast the same serialized bytes. A retry path that re-signs is a defect.
- Capture blockhash with `last_valid_block_height`; confirm by block height, not `time.sleep`.
- Priority fees via compute-budget instructions, capped, non-zero on mainnet.

## Guardrails & secrets
- Every action passes a `guard()` (allowlist + caps) before any send.
- Secrets from `os.environ` / secret manager only; load once. Redact before logging — never `logging.exception` a path that touched key bytes without redaction.
- Dry-run default; live sends behind an explicit flag/env var.

## Errors & retries
- Distinguish retryable (429/5xx/timeout) from terminal (on-chain err, expired blockhash). Backoff with jitter; honor `Retry-After`.
- Two-strike rule: same failure twice → stop and surface.
- No bare `except:`. Catch specific exceptions; re-raise or journal-and-fail.

## Style
- Type hints on public functions; `mypy`-clean where practical.
- Pure decision function with no I/O, so it unit-tests without a network.
- `ruff`/`black` formatted.
