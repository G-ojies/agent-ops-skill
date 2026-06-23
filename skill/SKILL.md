---
name: agent-ops
description: Build and operate production-grade autonomous agents on Solana. Covers the agent control loop, transaction lifecycle (simulate-before-send, priority fees, durable nonces, confirmation, landing), RPC resilience (multi-provider failover, rate-limit-aware batching, backoff), key custody and signing, safety guardrails (spend caps, allowlists, dry-run, human-in-the-loop), observability (structured logs, heartbeats, audit trails), payout/claim verification, and agent testing on devnet/LiteSVM. For on-chain program development (Anchor, Pinocchio), delegates to the core solana-dev skill.
user-invocable: true
---

# Solana Agent Ops Skill

> **Extends**: [solana-dev-skill](../solana-dev/SKILL.md) — Core Solana development (programs, frontend, testing, security)

This skill is for the layer the other skills skip: taking an agent that *can* call Solana and making it safe to leave running unattended. An autonomous agent that signs transactions is a different risk class from a script a human babysits — it retries on its own, it spends real funds, and a single unhandled edge case (an expired blockhash, a 429, a duplicated submission, a leaked key) becomes a money-losing or fund-draining event. Everything here is about closing those gaps before they cost something.

## What This Skill Is For

Use this skill when the user asks for:

### Agent Architecture & Control Loop
- Designing an autonomous agent that observes → decides → acts on Solana
- Structuring the perceive/plan/act loop with idempotency and crash-safety
- State persistence, run journaling, and resumable execution
- Scheduling, polling, and event-driven triggers (webhooks, log subscriptions)

### Transaction Lifecycle (the dangerous part)
- Simulate-before-send and reading simulation results correctly
- Priority fees and compute budget (`ComputeBudgetProgram`) sized to current network conditions
- Blockhash handling, `lastValidBlockHeight` expiry, and confirmation-by-blockheight
- Durable nonces for long-lived or offline signing
- Retry/rebroadcast strategy that does **not** create duplicate transactions
- Landing reliability: preflight tradeoffs, Jito tips/bundles, send pacing

### RPC Resilience & Cost
- Multi-provider failover (Helius / Triton / QuickNode / public) with health checks
- Rate-limit-aware batching, `429` backoff, and request budgeting
- Choosing commitment levels and avoiding RPC-induced inconsistency

### Key Custody & Signing
- Where keys live (env vs file vs KMS/HSM vs remote signer) and how to choose
- Never-log-secrets discipline and redaction
- Separating a hot operational key from treasury, scoping permissions

### Safety Guardrails
- Spend caps, per-tx and per-window limits, destination allowlists
- Dry-run / `--yes` gating and human-in-the-loop checkpoints
- Kill switches and circuit breakers

### Observability & Accounting
- Structured logging, heartbeats, and alerting that pages a human only when it should
- Audit trails that let you reconstruct every action and signature after the fact
- Payout/claim verification and reconciliation

### Program Development (Delegate to Core Skill)
- For Anchor programs → [programs-anchor.md](../solana-dev/programs-anchor.md)
- For Pinocchio programs → [programs-pinocchio.md](../solana-dev/programs-pinocchio.md)
- For IDL/codegen → [idl-codegen.md](../solana-dev/idl-codegen.md)
- For client/program security review → [security.md](../solana-dev/security.md)

## Default Stack Decisions (Opinionated)

### 1) SDK: `@solana/kit` (web3.js v2) first
- `@solana/kit` for transaction building, signing, and RPC
- `@solana-program/compute-budget` for priority fees / CU limits
- Fall back to `@solana/web3.js` v1 only when a dependency requires it — see [transactions.md](transactions.md) for the interop boundary
- Python agents: `solana-py` + `solders`; the lifecycle rules are identical

### 2) Confirmation: blockheight-based, never naive polling
- Always capture `{ blockhash, lastValidBlockHeight }` together
- Confirm against `lastValidBlockHeight`; treat expiry as a definitive terminal state, not a timeout
- Default commitment: `confirmed` for action, `finalized` for accounting/payout verification

### 3) Sending: simulate first, send with a retry budget
- Simulate every action transaction before the first send
- Keep preflight ON by default; only `skipPreflight: true` with an explicit reason and your own simulation upstream
- Rebroadcast the *same signed transaction* until blockhash expiry — never re-sign on retry (that is how you double-spend)

### 4) Keys: hot operational key, least privilege
- One scoped hot key for operations, separate from any treasury
- Keys from env/secret manager, never hardcoded, never logged
- Prefer a remote signer / KMS for anything holding meaningful value

### 5) Safety: closed by default
- Dry-run is the default; real sends require an explicit opt-in flag
- Hard spend cap and destination allowlist enforced in code, not just config
- A kill switch that halts the loop without losing in-flight state

### 6) RPC: at least two providers
- Primary + fallback with health checks; never depend on a single endpoint
- Respect rate limits proactively; back off on `429` with jitter

## Operating Procedure

### 1. Classify the Task Layer

| Layer | Examples | Skill File(s) |
|-------|----------|---------------|
| Agent loop & state | Control loop, scheduling, resumability | [architecture.md](architecture.md) |
| Transactions | Simulate, fees, confirm, retry, land | [transactions.md](transactions.md) |
| RPC / network | Failover, rate limits, backoff | [reliability.md](reliability.md) |
| Keys / signing | Custody, redaction, remote signers | [key-custody.md](key-custody.md) |
| Guardrails | Spend caps, allowlists, dry-run, kill switch | [safety.md](safety.md) |
| Logging / alerts | Structured logs, heartbeats, audit trail | [observability.md](observability.md) |
| Payouts | Claim flows, reconciliation, verification | [payouts.md](payouts.md) |
| Testing | Devnet, LiteSVM, RPC mocking, replay | [testing.md](testing.md) |
| Program logic | On-chain Anchor/Pinocchio | [programs-anchor.md](../solana-dev/programs-anchor.md) |

### 2. Pick the Right Agent

| Task Type | Agent | Model |
|-----------|-------|-------|
| Architecture, risk design, threat model | agent-architect | opus |
| Transaction / RPC / loop implementation | tx-engineer | sonnet |
| Pre-launch safety & key-custody review | safety-reviewer | opus |

### 3. Apply the Non-Negotiables

Before any agent sends a transaction unattended, all of these must be true:

1. **Simulate-before-send** on the first attempt of every action.
2. **Idempotency** — a crash mid-loop must not double-submit. Persist intent before sending; key actions by a stable client-side id.
3. **Bounded retries on the same signed tx** — rebroadcast until blockhash expiry, never re-sign on retry.
4. **Spend cap + allowlist enforced in code** — config alone is not a control.
5. **Secrets never logged** — redact before any log/heartbeat/alert leaves the process.
6. **A kill switch** — the loop can be stopped without corrupting state.

### 4. Add Tests

- **Unit**: pure decision logic with mocked RPC (see [testing.md](testing.md))
- **Simulation**: every transaction path through `simulateTransaction` / LiteSVM
- **Failure injection**: 429s, timeouts, expired blockhash, RPC disagreement
- **Devnet dry-run**: full loop against devnet before any mainnet key is loaded
- **Two-strike rule**: if the same send fails twice, STOP and surface — do not keep burning fees

### 5. Deliverables

When implementing, provide:
- Exact files changed with clear diffs
- The dry-run output of any action before it goes live
- Dependencies (package.json / requirements.txt) and run commands
- The guardrail configuration (caps, allowlists) in plain sight

---

## Progressive Disclosure (Read When Needed)

### Agent Ops Skills (This Skill)

- [architecture.md](architecture.md) — Control loop, state, idempotency, crash-safety, scheduling
- [transactions.md](transactions.md) — Simulate, priority fees, blockhash/expiry, confirmation, retries, durable nonces, landing
- [reliability.md](reliability.md) — RPC failover, rate limits, `429` backoff, commitment, request budgeting
- [key-custody.md](key-custody.md) — Key storage, redaction, hot vs treasury, remote signers/KMS
- [safety.md](safety.md) — Spend caps, allowlists, dry-run gating, human-in-the-loop, kill switch
- [observability.md](observability.md) — Structured logs, heartbeats, alerting, audit trail
- [payouts.md](payouts.md) — Claim flows, payout verification, reconciliation
- [testing.md](testing.md) — Devnet, LiteSVM, RPC mocking, failure injection, replay
- [resources.md](resources.md) — Curated SDK / RPC / tooling links

### Core Solana Dev Skills (from solana-dev-skill)

> Provided by [solana-dev-skill](../solana-dev/SKILL.md) — install if not present

- [programs-anchor.md](../solana-dev/programs-anchor.md) — Anchor framework patterns
- [programs-pinocchio.md](../solana-dev/programs-pinocchio.md) — High-performance programs
- [idl-codegen.md](../solana-dev/idl-codegen.md) — IDL generation, client codegen
- [testing.md](../solana-dev/testing.md) — LiteSVM, Mollusk, Surfpool
- [security.md](../solana-dev/security.md) — Program + client security checklists

---

## Task Routing Guide

| User asks about... | Primary skill file(s) |
|--------------------|----------------------|
| Building an autonomous agent / bot | architecture.md |
| Agent control loop / scheduling | architecture.md |
| Crash-safety / resumable runs | architecture.md |
| Idempotency / avoiding double-sends | architecture.md, transactions.md |
| Simulate a transaction | transactions.md |
| Priority fees / compute budget | transactions.md |
| Transaction not landing / dropped | transactions.md, reliability.md |
| Blockhash expired / `BlockhashNotFound` | transactions.md |
| Confirming a transaction | transactions.md |
| Durable nonce / offline signing | transactions.md |
| Jito tips / bundles | transactions.md |
| RPC failover / multiple providers | reliability.md |
| Rate limited / `429` errors | reliability.md |
| Which commitment level | reliability.md |
| Where to store the private key | key-custody.md |
| Keys are leaking into logs | key-custody.md, observability.md |
| Remote signer / KMS / HSM | key-custody.md |
| Spend limits / allowlists | safety.md |
| Dry-run / confirmation gating | safety.md |
| Kill switch / circuit breaker | safety.md |
| Logging / heartbeats / alerts | observability.md |
| Audit trail / reconstructing actions | observability.md |
| Verifying a payout / claim | payouts.md |
| Testing the agent / devnet | testing.md |
| Mocking RPC in tests | testing.md |
| **Anchor program** | solana-dev → programs-anchor.md |
| **Pinocchio program** | solana-dev → programs-pinocchio.md |
| **Program security review** | solana-dev → security.md |

---

## Commands

| Command | Description |
|---------|-------------|
| /simulate-tx | Simulate a transaction and explain the result (CU usage, logs, errors) before any send |
| /agent-dry-run | Run the agent loop end-to-end with sends disabled, showing every action it *would* take |
| /safety-review | Run the pre-launch guardrail + key-custody checklist against the codebase |
| /quick-commit | Quick commit with conventional messages |

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **agent-architect** | opus | Agent design, control-loop architecture, risk/threat modeling, state design |
| **tx-engineer** | sonnet | Transaction lifecycle, RPC, retries, and loop implementation |
| **safety-reviewer** | opus | Pre-launch review of guardrails, key custody, and failure handling |
