# RPC Resilience & Cost

An agent is only as reliable as the RPC it depends on. A single endpoint *will* rate-limit you, return stale reads, or go down — and when it does at 3am, an unsupervised agent either stalls or, worse, acts on bad data. This file is about never depending on one endpoint and never tripping over a rate limit you could have anticipated.

## Use at least two providers with health checks

```ts
const providers = [
  { name: 'helius',   rpc: createSolanaRpc(HELIUS_URL),   weight: 1 },
  { name: 'triton',   rpc: createSolanaRpc(TRITON_URL),   weight: 1 },
  { name: 'public',   rpc: createSolanaRpc(PUBLIC_URL),   weight: 0 },  // last resort
];

async function healthy(p) {
  try { return (await p.rpc.getHealth().send()) === 'ok'; }
  catch { return false; }
}
```

Failover policy:
- **Reads**: try primary; on `429`/`5xx`/timeout, fail over to the next healthy provider. Reads are idempotent, so retrying elsewhere is free.
- **Sends**: this is different — see the warning below.
- **Health**: poll `getHealth` periodically and route around an unhealthy provider proactively, not just reactively.

> **Failover on sends is not a free retry.** Sending the *same signed transaction* to multiple providers is fine and even improves landing — the network deduplicates identical bytes. What is never safe is letting a "send failed, try another provider" path *re-sign* a new transaction. Keep the [transactions.md](transactions.md) rule: rebroadcast the same bytes anywhere; re-sign nowhere.

## Respect rate limits before you hit them

Reacting to `429` is the fallback; budgeting requests is the discipline. Most provider plans are credits-per-second. Track your spend and pace.

```ts
// Token-bucket limiter: cap sustained request rate, allow small bursts.
class RateLimiter {
  constructor(ratePerSec, burst) { this.rate = ratePerSec; this.tokens = burst; this.max = burst; this.last = null; }
  async take() {
    // (refill based on elapsed wall-clock, then await if empty)
  }
}
```

- **Batch reads** — `getMultipleAccounts` instead of N× `getAccountInfo`; one `getSignatureStatuses([...])` for many signatures.
- **Cache the cheap-but-hot calls** — e.g. don't fetch a fresh blockhash for every action when one is valid for ~60–90s.
- **Subscribe instead of poll** where you can (`accountSubscribe`/`logsSubscribe`), with a polling backstop ([architecture.md](architecture.md)).

## Backoff with jitter on `429`/`5xx`

```ts
async function withBackoff(fn, { tries = 5, base = 500, cap = 8000 } = {}) {
  for (let i = 0; i < tries; i++) {
    try { return await fn(); }
    catch (e) {
      if (!isRetryable(e) || i === tries - 1) throw e;
      const backoff = Math.min(cap, base * 2 ** i);
      const jitter = backoff * 0.5 * Math.random();   // de-sync concurrent retries
      await sleep(backoff + jitter);
    }
  }
}
// Honor a Retry-After header if the provider sends one — it beats your guess.
```

Jitter matters: without it, every retry from every worker fires at the same instant and you re-thunder the endpoint you're trying to recover from.

## Commitment levels — match to consequence

| Commitment | Latency | Reorg risk | Use for |
|------------|---------|-----------|---------|
| `processed` | lowest | can be rolled back | UI hints only — never decisions |
| `confirmed` | ~1–2s | very low | the default for *acting* |
| `finalized` | slowest | effectively zero | accounting, payouts, anything money-final ([payouts.md](payouts.md)) |

The trap: reading at `processed`, deciding on it, and acting — then the read gets rolled back and your action was based on state that never happened. **Decide on `confirmed`; verify money on `finalized`.**

## Guard against RPC disagreement

Two providers can briefly report different state (different slots). For consequential decisions, read the slot alongside the data and prefer the more advanced provider, or require agreement before acting. For sends, always confirm against the *same* provider/subscription you're polling.

## Checklist

- [ ] ≥2 providers with periodic `getHealth` checks
- [ ] Reads fail over freely; sends rebroadcast same bytes, never re-sign
- [ ] Proactive rate limiting (token bucket) + reactive backoff with jitter
- [ ] `Retry-After` honored when present
- [ ] Reads batched; blockhash/hot reads cached
- [ ] `confirmed` to act, `finalized` to settle money
