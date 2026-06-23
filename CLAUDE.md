# Agent Ops — Claude Code Configuration

This skill is loaded. When the user is building or operating an **autonomous Solana agent** — anything that signs and sends transactions without a human watching each one — route through `skill/SKILL.md` and apply these defaults.

## When this skill applies
- "Build an agent/bot that..." that transacts on Solana
- Anything about transaction retries, landing, confirmation, priority fees on an automated path
- RPC failover / rate limiting for an unattended process
- Key custody / signing for a service
- Spend limits, dry-run, kill switches, agent safety
- Payout/claim verification and reconciliation

## The non-negotiables (always enforce)
1. **Simulate before the first send.**
2. **Never re-sign on retry** — rebroadcast the same signed bytes. Re-signing is the classic double-spend.
3. **Confirm by blockheight expiry**, not by sleeping.
4. **Idempotency** — journal intent before send; reconcile against the chain on startup.
5. **Guardrails in code** — allowlist + spend caps between DECIDE and ACT.
6. **Secrets never logged** — redact at every boundary.
7. **Dry-run is the default**; live sends require an explicit flag.
8. **There is always a kill switch.**

## Routing
Read `skill/SKILL.md` first; it has the full task-routing table. For on-chain program work, delegate to the core `solana-dev` skill.

## Agents
- **agent-architect** (opus) — design the loop, state, risk model
- **tx-engineer** (sonnet) — implement tx lifecycle / RPC / loop
- **safety-reviewer** (opus) — adversarial pre-launch review

## Commands
`/simulate-tx`, `/agent-dry-run`, `/safety-review`, `/quick-commit`

## Two-strike rule
If the same send fails twice, STOP and surface the error and the transaction — do not keep retrying and burning fees.
