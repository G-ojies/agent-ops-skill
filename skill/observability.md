# Observability & Accounting

An unattended agent that you can't see into is a black box that spends money. Observability is what lets you answer, after the fact, *exactly what it did and why* — and lets it page you the moment something is wrong, without drowning you in noise the rest of the time. Three layers: **structured logs** (what happened), **heartbeats** (it's alive and healthy), **audit trail** (the legally/financially reconstructable record).

## Structured logs

Log machine-parseable events, not prose. Every action-related log carries the action id ([architecture.md](architecture.md)) so you can trace one action across its whole lifecycle.

```ts
log.info({ evt: 'action.decided', actionId, kind, target, lamports });
log.info({ evt: 'action.simulated', actionId, unitsConsumed, ok: true });
log.info({ evt: 'action.sent', actionId, sig });
log.info({ evt: 'action.confirmed', actionId, sig, slot });
log.error({ evt: 'action.failed', actionId, reason: classify(err) });
```

- **One event per lifecycle transition**, keyed by `actionId` — `grep` by id reconstructs the action's whole story.
- **Levels mean something**: `info` = normal lifecycle, `warn` = recovered (failover, retry), `error` = action failed, `fatal` = breaker tripped / halting.
- **Redact first.** Every log line goes through the redaction from [key-custody.md](key-custody.md). No exceptions on error paths.
- **Include the signature** on send/confirm so a human can open it in an explorer immediately.

## Heartbeats

A heartbeat proves the loop is alive *and* healthy, and is the basis for "the agent died" alerting. Emit one per tick with the state that matters.

```ts
function heartbeat(state) {
  return {
    status: state.breakerTripped ? 'degraded' : 'ok',
    time: new Date().toISOString(),
    lastAction: state.lastAction,
    nextAction: state.nextAction,
    spentInWindow: state.spentInWindow,
    hotBalance: state.hotBalance,        // watch this for unexpected drops
    errorsThisWindow: state.errors,
  };
}
```

The absence of a heartbeat is itself an alert: a watchdog that hasn't seen a heartbeat in N intervals pages a human (the agent crashed, hung, or lost connectivity). This is the inverse of error-based alerting and catches the failures that produce no error log because the process is simply gone.

## Alerting — page on signal, stay quiet otherwise

Alert fatigue makes people ignore the alert that matters. Page only on:
- **Breaker tripped / kill switch engaged** (fatal).
- **No heartbeat for N intervals** (dead/hung).
- **Balance dropped unexpectedly** — hot key down more than expected for the actions taken (possible compromise or bug).
- **Window spend cap hit** — the agent is being throttled by its own brake; something is off.
- **Approval requested** (if human-in-the-loop, [safety.md](safety.md)).

Everything else is a log you review on your schedule, not a page. Route pages to a real channel (Telegram/Slack/PagerDuty); route routine events to a dashboard or log store.

## Audit trail

The audit trail is the append-only, durable record that lets you reconstruct every action and prove what the agent did. It overlaps with the journal from [architecture.md](architecture.md) — make the journal *be* the audit trail.

Each entry: `actionId`, `decidedAt`, `intent` (full), `simulationResult`, `signature`, `confirmedSlot`, `outcome`, `guardChecks` (which caps it passed). Properties that make it trustworthy:
- **Append-only** — entries are never edited, only superseded.
- **Complete** — written before send (intent) and after confirm (outcome), so a crash leaves a visible `pending`.
- **Reconcilable** — every signature in the trail can be looked up on-chain to verify it matches.

This is what you hand a counterparty, an auditor, or yourself at 3am to answer "did the agent do this, and was it authorized?"

## Metrics worth tracking

Actions/hour, success rate, average priority fee paid, RPC error rate by provider, landing latency (send→confirm), spend vs cap utilization, hot-key balance over time. These turn "it feels slow / expensive" into a number you can act on.

## Checklist

- [ ] Structured events keyed by `actionId`, one per lifecycle transition
- [ ] Redaction applied to every log/heartbeat/alert
- [ ] Heartbeat per tick with balance + spend + health
- [ ] Watchdog alerts on missing heartbeat
- [ ] Pages reserved for breaker/dead/balance-drop/cap-hit/approval; rest is dashboard
- [ ] Append-only audit trail, reconcilable against on-chain signatures
