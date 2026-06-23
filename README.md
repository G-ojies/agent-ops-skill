# Solana Agent Ops Skill

A Claude Code / Codex skill for **building and operating autonomous agents on Solana** — agents that observe, decide, and sign transactions with no human watching each action.

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
![Stack: 2026](https://img.shields.io/badge/stack-2026-blue)
![SDK: @solana/kit](https://img.shields.io/badge/SDK-%40solana%2Fkit-blueviolet)

> **Extends**: [solana-dev-skill](https://github.com/solana-foundation/solana-dev-skill) — core Solana development (programs, frontend, testing, security)

## Why this skill

The kit already has skills for *writing* Solana programs and frontends. This one covers the layer they skip: taking an agent that *can* call Solana and making it **safe to leave running**.

An autonomous agent that signs transactions is a different risk class from a script a human babysits. It retries on its own, spends real funds, and a single unhandled edge case becomes a money-losing event:

- a **re-signed retry** → two transactions land → double-spend
- a blockhash **expiry** treated as a timeout → the loop spins forever on a dead tx
- a **crash mid-send** with no idempotency → a restart repeats the action
- a key in a **log line** → drained wallet
- a logic bug at **machine speed** → hundreds of bad transactions before anyone notices

This skill encodes the patterns that make each of those bounded.

```
┌───────────────────────────────────────────────────────────────┐
│                    agent-ops-skill                            │
│                                                              │
│   perceive → decide → GUARD → act → record   (the loop)      │
│                                                              │
│   ├── architecture   loop, state, idempotency, crash-safety  │
│   ├── transactions   simulate, fees, confirm, retry, land    │
│   ├── reliability    RPC failover, rate limits, backoff      │
│   ├── key-custody    hot vs treasury, redaction, remote sign │
│   ├── safety         caps, allowlist, dry-run, kill switch   │
│   ├── observability  logs, heartbeats, audit trail           │
│   ├── payouts        claim/payout verification, reconcile    │
│   └── testing        devnet, LiteSVM, failure injection      │
│                          │ delegates program work to ↓       │
│   ┌──────────────────────────────────────────────────────┐   │
│   │  solana-dev-skill (core): Anchor, Pinocchio, security │   │
│   └──────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────┘
```

## The non-negotiables

Before any agent sends a transaction unattended, all of these hold — they run through the whole skill:

1. **Simulate before the first send.**
2. **Never re-sign on retry** — rebroadcast the *same* signed bytes.
3. **Confirm by blockheight expiry**, never by sleeping.
4. **Idempotency** — journal intent before send; reconcile against the chain on startup.
5. **Guardrails in code** — allowlist + spend caps between DECIDE and ACT.
6. **Secrets never logged** — redact at every boundary.
7. **Dry-run is the default**; live sends require an explicit flag.
8. **There is always a kill switch.**

## What's included

| File | Covers |
|------|--------|
| [skill/architecture.md](skill/architecture.md) | Control loop, state, idempotency journal, crash-safety, triggers, single-flight |
| [skill/transactions.md](skill/transactions.md) | Simulate-before-send, priority fees, blockhash/expiry, confirmation, the cardinal retry rule, durable nonces, landing (Jito) |
| [skill/reliability.md](skill/reliability.md) | Multi-provider failover, rate-limit budgeting, `429` backoff with jitter, commitment levels |
| [skill/key-custody.md](skill/key-custody.md) | Hot vs treasury keys, storage tiers, remote signers/KMS, secret redaction, rotation |
| [skill/safety.md](skill/safety.md) | Spend caps, allowlists, dry-run gating, human-in-the-loop, kill switch, circuit breaker, input/oracle trust |
| [skill/observability.md](skill/observability.md) | Structured logs, heartbeats, watchdog alerting, append-only audit trail |
| [skill/payouts.md](skill/payouts.md) | Payout/claim verification at finality, reference matching, reconciliation |
| [skill/testing.md](skill/testing.md) | Pure-logic unit tests, simulation, failure injection, devnet dry-run, replay |
| [skill/resources.md](skill/resources.md) | Curated 2026 SDK / RPC / tooling links |

Plus `agents/` (architect, tx-engineer, safety-reviewer), `commands/` (`/simulate-tx`, `/agent-dry-run`, `/safety-review`, `/quick-commit`), and `rules/` (TypeScript, Python).

## Installation

```bash
git clone https://github.com/GreYat-Labs/agent-ops-skill
cd agent-ops-skill
./install.sh          # interactive, installs to ~/.claude/skills/agent-ops
./install.sh -y       # non-interactive, all defaults
./install.sh -p       # project-local (./.claude)
./install.sh --no-core   # skip the solana-dev-skill core dependency
```

The installer copies the skill into your Claude Code skills directory and pulls the `solana-dev-skill` core dependency (unless `--no-core`).

## Default stack (2026)

| Layer | Choice |
|-------|--------|
| Client SDK | `@solana/kit` (web3.js v2); `solana-py` + `solders` for Python |
| Fees | `@solana-program/compute-budget`, sized to recent fees, capped |
| Confirmation | blockheight-expiry based; `confirmed` to act, `finalized` to settle money |
| Keys | hot operational key separate from treasury; KMS/remote signer for real value |
| RPC | ≥2 providers (Helius / Triton / QuickNode) with health checks |
| Landing | sized priority fees; Jito bundles/tips when needed |
| Testing | LiteSVM + devnet dry-run before mainnet |

## Agents

| Agent | Model | Purpose |
|-------|-------|---------|
| **agent-architect** | opus | Loop/state/risk design before code |
| **tx-engineer** | sonnet | Transaction lifecycle, RPC, loop implementation |
| **safety-reviewer** | opus | Adversarial pre-launch review |

## Commands

| Command | Purpose |
|---------|---------|
| **/simulate-tx** | Simulate a transaction and explain it before any send |
| **/agent-dry-run** | Run the full loop with sends disabled |
| **/safety-review** | Pre-launch guardrail + key-custody checklist |
| **/quick-commit** | Conventional commit with a secret scan |

## Usage examples

```
"Design an autonomous agent that claims Solana rewards safely"
"Review my agent's retry path — am I re-signing on retry?"
"Add a spend cap and destination allowlist to this send function"
"My transactions keep dropping under load — fix the landing logic"
"/safety-review"  (before going live)
```

## Repository structure

```
agent-ops-skill/
├── LICENSE                  # MIT
├── README.md                # this file
├── CLAUDE.md                # Claude Code configuration
├── install.sh               # installer
├── skill/
│   ├── SKILL.md             # entry point + routing tables
│   ├── architecture.md
│   ├── transactions.md
│   ├── reliability.md
│   ├── key-custody.md
│   ├── safety.md
│   ├── observability.md
│   ├── payouts.md
│   ├── testing.md
│   └── resources.md
├── agents/                  # agent-architect, tx-engineer, safety-reviewer
├── commands/                # simulate-tx, agent-dry-run, safety-review, quick-commit
└── rules/                   # typescript.md, python.md
```

## Design notes

- **Progressive disclosure**: `SKILL.md` is a thin routing hub; the heavy content in each `skill/*.md` loads only when the task needs it — token-efficient by construction.
- **Delegate, don't duplicate**: program development, on-chain security, and core testing are delegated to `solana-dev-skill` via relative links rather than re-implemented.
- **Production-grade, not toy**: every section ends in a checklist, and the safety/transaction rules are enforced down to the `rules/` files so generated code inherits them.

## Contributing

1. Fork the repo
2. Create a feature branch: `git checkout -b feat/my-change`
3. Make your changes (keep the delegate-don't-duplicate principle)
4. Open a PR

## License

MIT — see [LICENSE](LICENSE).

---

Built by [GreYat Labs](https://github.com/GreYat-Labs) for the [Solana AI Kit](https://github.com/solanabr/solana-ai-kit) skill bounty.
