# Agent Architecture & Control Loop

The shape of every autonomous Solana agent is the same: **perceive → decide → act → record**, on a loop. What separates a production agent from a demo is what happens when that loop is interrupted — by a crash, a restart, a network blip, or a duplicate trigger. This file is about making the loop safe to leave running.

## The control loop

```
loop:
  1. PERCEIVE  — read on-chain + off-chain state (RPC, APIs, queues)
  2. DECIDE    — pure function: state -> list of intended actions
  3. GUARD     — apply safety checks (caps, allowlist, kill switch) -> filtered actions
  4. ACT       — for each action: persist intent, build+sign+send, confirm
  5. RECORD    — write outcome to the journal; emit heartbeat
  sleep / await next trigger
```

Two design rules make this robust:

- **Keep DECIDE pure.** It takes a snapshot of state and returns *intended actions* with no side effects. Pure decision logic is the part you can unit-test exhaustively (see [testing.md](testing.md)) and the part a reviewer can actually reason about.
- **Persist intent before acting.** The window between "decided to send" and "send confirmed" is where crashes cause double-spends. Write the intended action — with a stable client-generated id — to durable storage *before* the send, and reconcile on startup.

## Idempotency: the property that prevents double-spends

An agent that restarts must not repeat an action it already took. This is the single most important correctness property and the one most demos get wrong.

**Pattern: intent journal keyed by a deterministic id.**

```ts
// A stable id derived from WHAT the action is, not when it ran.
// Same logical action => same id => deduplicated across restarts.
const actionId = hash(`${agentRun}:${target}:${nonce}`);

if (await journal.isDone(actionId)) return;          // already completed
await journal.markPending(actionId, intent);         // durable, BEFORE sending
const sig = await execute(intent);                   // build + sign + send + confirm
await journal.markDone(actionId, { sig });           // durable, AFTER confirm
```

On startup, scan the journal for `pending` entries and **reconcile before doing anything new**:

```ts
for (const entry of await journal.pending()) {
  // Did the tx we may have sent actually land? Check the chain, don't re-send blindly.
  const landed = await findLandedSignature(entry);   // by reference/memo/account state
  if (landed) await journal.markDone(entry.id, { sig: landed });
  else await journal.markFailed(entry.id);            // safe to retry as a new action
}
```

The reconciliation step is what makes "persist intent before send" safe: a crash between send and confirm leaves a `pending` entry, and startup decides its fate by **looking at the chain**, not by re-sending. Tie the on-chain lookup to something deterministic — a memo, a reference pubkey, or the resulting account state — so you can always answer "did this specific action happen?"

## State & persistence

- **Journal** (append-only): every intended and completed action, with ids, signatures, timestamps. This is also your audit trail (see [observability.md](observability.md)).
- **Cursor**: where the agent is in its work (last processed slot, last seen listing id, last block scanned). Persist it *after* the corresponding work is journaled, never before.
- **Config vs secrets**: config (caps, allowlists, intervals) in a checked-in file; secrets only from the environment / a secret manager (see [key-custody.md](key-custody.md)).

Storage choice scales with stakes: a JSON/SQLite file is fine for a single-instance agent; use Postgres/Redis when multiple workers or restarts across machines are involved. The *pattern* doesn't change — only the durability guarantee does.

## Triggers: polling vs event-driven

| Trigger | Use when | Watch out for |
|---------|----------|---------------|
| Interval polling | Simple, low-frequency tasks | Wastes RPC budget; add jitter, respect rate limits ([reliability.md](reliability.md)) |
| `logsSubscribe` / `accountSubscribe` (WS) | React to on-chain events fast | WS drops silently — add reconnect + a polling backstop to catch missed events |
| Webhooks (Helius, etc.) | Push-based, scalable indexing | Verify signatures; webhooks can duplicate — dedupe by event id |
| Cron / scheduler | Time-based jobs | A long run can overlap the next tick — guard with a single-flight lock |

**Always run a reconciliation/backstop pass** even with push triggers. WebSockets reconnect and miss events; webhooks retry and duplicate. The periodic "scan from last cursor" loop is what guarantees you eventually process everything exactly once.

## Single-flight: don't run two copies

Two instances of the same agent acting on the same state will double-act. Enforce single-flight with a lock (a lockfile with PID + heartbeat for single-host; a Redis/DB advisory lock for multi-host) and have each tick check the lock before DECIDE.

## Crash-safety checklist

- [ ] Intent is journaled durably **before** any send
- [ ] Startup reconciles `pending` entries against the chain before new work
- [ ] Action ids are deterministic, so a replay maps to the same id
- [ ] Cursor advances only after work is journaled
- [ ] A single-flight lock prevents concurrent instances
- [ ] The loop can be stopped by the kill switch without corrupting state ([safety.md](safety.md))

## Delegation

- On-chain program logic the agent calls → [programs-anchor.md](../solana-dev/programs-anchor.md)
- The mechanics of building/sending/confirming a transaction → [transactions.md](transactions.md)
- Making RPC reads in PERCEIVE reliable → [reliability.md](reliability.md)
