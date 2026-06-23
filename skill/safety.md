# Safety Guardrails

An autonomous agent does what its code allows, at machine speed, with no one watching. A logic bug, a bad oracle read, or a prompt-injected instruction can turn into hundreds of transactions before anyone notices. Guardrails are the layer that makes the *worst case* bounded. The governing principle: **closed by default** — the agent can do nothing harmful until explicitly, narrowly permitted, and there is always a way to stop it instantly.

## Enforce limits in code, not just config

Config is a setting; a control is code that *cannot be bypassed by the normal action path*. Put the hard limits between DECIDE and ACT, as a guard every action must pass.

```ts
function guard(action, state) {
  // 1. Destination allowlist — can we even send here?
  if (!ALLOWLIST.has(action.destination)) throw new Blocked('destination not allowlisted');

  // 2. Per-transaction cap
  if (action.lamports > MAX_PER_TX) throw new Blocked('exceeds per-tx cap');

  // 3. Rolling-window cap — the spend-velocity brake
  if (state.spentInWindow + action.lamports > MAX_PER_WINDOW) throw new Blocked('window spend cap hit');

  // 4. Per-tick action cap — a loop bug can't fire 500 txs
  if (state.actionsThisTick >= MAX_ACTIONS_PER_TICK) throw new Blocked('action rate cap hit');

  return action;
}
```

The four caps cover the realistic failure modes: a single oversized send (per-tx), a slow drain (window), and a runaway loop (per-tick + window). The allowlist is what makes a *compromised* agent still unable to send to an attacker's address — which is why, for real value, it should also be enforced one layer down at the signer/policy ([key-custody.md](key-custody.md)).

## Dry-run is the default; real sends are opt-in

Sending real transactions must require an explicit, visible decision — never the default of running the program.

```ts
const LIVE = process.argv.includes('--yes') || process.env.AGENT_LIVE === '1';

async function execute(action) {
  if (!LIVE) { log.info(`DRY-RUN would send: ${describe(action)}`); return { dryRun: true }; }
  return await send(action);   // real
}
```

- **Default = dry-run.** Every action prints exactly what it *would* do. This is also the `/agent-dry-run` command.
- **Live requires a flag** (`--yes` / `AGENT_LIVE=1`). No environment, no flag, no spend.
- **Staged rollout**: dry-run → devnet live → mainnet with tiny caps → raise caps. Never go straight to mainnet with production caps.

## Human-in-the-loop for the consequential actions

Not every action needs approval, but the irreversible or large ones do. Gate by threshold.

```ts
if (action.lamports > APPROVAL_THRESHOLD || action.irreversible) {
  await requestApproval(action);      // Telegram/Slack prompt, blocks until approved/denied/timeout
}
```

Approval that times out should **deny**, not proceed. A human who didn't answer is not a yes.

## Kill switch & circuit breaker

There must be a way to stop the agent *now* that doesn't corrupt in-flight state ([architecture.md](architecture.md) journals make this safe).

```ts
// Kill switch: checked at the top of every tick and before every send.
if (await killSwitch.engaged()) { log.warn('kill switch engaged — halting'); return shutdownGracefully(); }
```

- **Kill switch**: a file, a flag in a DB row, or a control message. Checked before DECIDE and again before each send, so engaging it stops new actions immediately while letting an in-flight confirm finish and journal.
- **Circuit breaker**: trips automatically on anomalies — N consecutive failures, error rate over a threshold, an unexpected balance delta, simulation results that don't match expectations. A tripped breaker halts and pages a human; it does not auto-reset.

## Validate inputs and oracle reads — especially for AI-driven agents

If decisions come from an LLM, an external API, or an on-chain oracle, treat that input as untrusted:
- **Bound the output.** An LLM/agent decision still passes through `guard()` — natural language can suggest an action, it can never bypass a cap or allowlist.
- **Sanity-check oracle/price reads** against a second source or a plausibility range before acting on them. A bad price feed is a classic drain vector.
- **Prompt injection is a live threat.** Data the agent reads (listing text, on-chain memos, API payloads) can contain instructions. The caps/allowlist are what make injection non-catastrophic — the agent literally cannot act outside them.

## Pre-launch safety checklist (this is `/safety-review`)

- [ ] Allowlist + per-tx + rolling-window + per-tick caps enforced in code before ACT
- [ ] For real value: caps/allowlist also enforced at the signer/policy layer
- [ ] Dry-run is the default; live requires an explicit flag
- [ ] Staged rollout path (dry-run → devnet → small mainnet → scale)
- [ ] Human approval gate for actions over threshold; timeout = deny
- [ ] Kill switch checked before DECIDE and before every send
- [ ] Circuit breaker on consecutive failures / anomalies, no auto-reset
- [ ] All external/LLM/oracle inputs pass through the same guard; oracle reads sanity-checked
- [ ] Secrets redacted everywhere ([key-custody.md](key-custody.md))
