# Transaction Lifecycle

This is the file the whole skill exists for. An autonomous agent that signs and sends transactions without a human watching has to get the full lifecycle right — **build → simulate → size fees → sign → send → confirm → retry-or-fail** — because every gap is a way to lose funds, leak duplicates, or spin forever on a dead transaction.

Examples use `@solana/kit` (web3.js v2), the current default. The same lifecycle applies to `solana-py`/`solders` and web3.js v1 — only the API names change.

## 1. Build with an explicit lifetime

A transaction's "lifetime" is what bounds how long it can land. For normal sends that's a recent blockhash, captured **together with** its `lastValidBlockHeight` — you need both to confirm correctly.

```ts
import {
  createSolanaRpc, createSolanaRpcSubscriptions, pipe,
  createTransactionMessage, setTransactionMessageFeePayerSigner,
  setTransactionMessageLifetimeUsingBlockhash,
  appendTransactionMessageInstructions,
} from '@solana/kit';

const rpc = createSolanaRpc(RPC_URL);
const { value: latestBlockhash } = await rpc.getLatestBlockhash({ commitment: 'confirmed' }).send();

let txMessage = pipe(
  createTransactionMessage({ version: 0 }),                                  // always v0
  m => setTransactionMessageFeePayerSigner(signer, m),
  m => setTransactionMessageLifetimeUsingBlockhash(latestBlockhash, m),      // carries lastValidBlockHeight
  m => appendTransactionMessageInstructions(instructions, m),
);
```

**Rule:** capture `{ blockhash, lastValidBlockHeight }` as a pair and keep them. The blockhash decides validity; `lastValidBlockHeight` is how you know when it's *permanently* dead.

## 2. Simulate before the first send — always

Simulation is free and catches the failure before it costs a fee or, worse, half-executes. An unattended agent must never send an action it hasn't simulated.

```ts
import { getBase64EncodedWireTransaction, signTransactionMessageWithSigners } from '@solana/kit';
// signTransactionMessageWithSigners is async and compiles internally — no separate compile step.

const signed = await signTransactionMessageWithSigners(txMessage);
const wire = getBase64EncodedWireTransaction(signed);

const sim = await rpc.simulateTransaction(wire, {
  encoding: 'base64',
  replaceRecentBlockhash: false,   // we want to test THIS blockhash
  sigVerify: true,
}).send();

if (sim.value.err) {
  // Do NOT send. Log sim.value.logs, classify the error, and stop or adapt.
  throw new SimulationFailed(sim.value.err, sim.value.logs);
}
const unitsConsumed = sim.value.unitsConsumed;  // bigint | undefined — drives the CU limit below
```

Read the result properly: `err` means it will fail on-chain — never send it. `logs` tell you *why*. `unitsConsumed` is what you use to set the compute-unit limit precisely instead of guessing.

## 3. Size priority fees to current conditions

Priority fees are how a transaction competes for block space. Hardcoding them either overpays constantly or fails to land when the network is busy. Set a **compute-unit limit** (from simulation) and a **compute-unit price** (from recent network data), via `@solana-program/compute-budget`.

```ts
import { getSetComputeUnitLimitInstruction, getSetComputeUnitPriceInstruction } from '@solana-program/compute-budget';

// Limit: measured units + a margin, so you don't overpay for headroom you don't use.
// unitsConsumed is optional — fall back to a safe default if simulation didn't report it.
const cuLimit = Math.ceil(Number(unitsConsumed ?? 200_000n) * 1.1);

// Price: sample recent fees for the accounts this tx writes to, pick a percentile.
const recent = await rpc.getRecentPrioritizationFees(writableAccounts).send();
const fees = recent.map(r => Number(r.prioritizationFee)).sort((a, b) => a - b);
const microLamports = percentile(fees, 0.75) || 1_000;   // floor so it's never zero

const withBudget = pipe(
  txMessage,
  m => appendTransactionMessageInstructions([
    getSetComputeUnitLimitInstruction({ units: cuLimit }),
    getSetComputeUnitPriceInstruction({ microLamports }),
  ], m),
);
```

Adding the budget instructions changes the message, so **re-simulate or at least re-sign** after this step. Use a percentile (P75–P90 when you need reliability), cap it so a fee spike can't drain you, and never let the price be zero on mainnet.

## 4. Send and confirm by blockheight (not by sleeping)

The correct confirmation model is: rebroadcast the **same signed transaction** and poll its status until it confirms *or* the chain passes `lastValidBlockHeight`. Blockhash expiry is a definitive terminal state — once passed, that exact transaction can never land, so you stop cleanly instead of waiting on an arbitrary timeout.

The high-level helper does this for you:

```ts
import { sendAndConfirmTransactionFactory, getSignatureFromTransaction } from '@solana/kit';

const rpcSubscriptions = createSolanaRpcSubscriptions(WS_URL);
const sendAndConfirm = sendAndConfirmTransactionFactory({ rpc, rpcSubscriptions });

try {
  await sendAndConfirm(signed, { commitment: 'confirmed' });
  const sig = getSignatureFromTransaction(signed);   // deterministic id BEFORE sending
} catch (e) {
  // Either it failed on-chain, or the blockhash expired. Both are terminal for THIS tx.
}
```

If you need manual control (custom rebroadcast pacing, your own retry budget), the loop is:

```ts
const sig = getSignatureFromTransaction(signed);     // known before the first send
while (true) {
  await rpc.sendTransaction(wire, { encoding: 'base64', skipPreflight: true, maxRetries: 0n }).send();  // maxRetries is a bigint in kit
  await sleep(2000);

  const { value } = await rpc.getSignatureStatuses([sig]).send();
  const st = value[0];
  if (st?.confirmationStatus === 'confirmed' || st?.confirmationStatus === 'finalized') {
    if (st.err) throw new TxFailedOnChain(st.err);
    break;                                            // landed
  }
  const height = await rpc.getBlockHeight({ commitment: 'confirmed' }).send();
  if (height > latestBlockhash.lastValidBlockHeight) throw new BlockhashExpired();  // terminal
}
```

`skipPreflight: true` here is deliberate and safe **only because you already simulated in step 2** — re-running preflight on every rebroadcast wastes RPC and time. `maxRetries: 0n` hands rebroadcast control to your loop.

## 5. The cardinal retry rule

> **Rebroadcast the same signed transaction. Never re-sign on retry.**

The transaction signature is computed from the message, which includes the blockhash. As long as you resend the *same bytes*, the network deduplicates it — validators keep a status cache keyed on the transaction's message hash and reject a repeat as `AlreadyProcessed`, so sending it ten times can land at most once (and once the blockhash expires it fails `BlockhashNotFound` and can never re-land). The moment you build a *new* transaction (new blockhash, new instructions) to "retry," you've created a second action that can also land. That is the classic autonomous-agent double-spend. Retries live at the *network* layer (rebroadcast same bytes); a genuinely new attempt only happens **after** the old one is provably dead (expired), and it must go through the same idempotency journal ([architecture.md](architecture.md)).

## 6. Durable nonces — for long-lived or offline signing

When an action can't be built and landed inside the ~60–90s blockhash window (offline signing, multisig collection, scheduled execution), use a **durable nonce** instead of a blockhash. The nonce account's stored value acts as the lifetime and only advances when an `advanceNonce` instruction (the required first instruction) executes.

```ts
import { setTransactionMessageLifetimeUsingDurableNonce } from '@solana/kit';
// First instruction MUST be the nonce advance; the tx stays valid until that nonce is consumed.
```

Confirm durable-nonce transactions with `sendAndConfirmDurableNonceTransactionFactory` — a blockhash-lifetime tx and a nonce-lifetime tx are different types, so the regular `sendAndConfirmTransactionFactory` won't accept a nonce tx.

Key discipline: the nonce advances exactly once per successful use, so durable-nonce transactions are naturally single-use — but you must still journal intent, because a signed-but-unsent nonce tx is a live liability until the nonce moves.

## 7. Landing reliability

When the network is congested, sized priority fees are the first lever. Beyond that:

- **Send to a staked/known-good RPC** — landing rates differ sharply between providers ([reliability.md](reliability.md)).
- **Pace rebroadcasts** (every ~2s), don't hammer — you'll just hit rate limits.
- **Jito bundles / tips**: for atomic multi-tx actions or when you need stronger inclusion guarantees, submit through a block-engine with a tip instruction. Bundles are all-or-nothing, which is itself a safety property for multi-step actions. Treat the tip like a priority fee: size it, cap it.
- **Version everything v0** so you can use Address Lookup Tables for large transactions.

## Common errors & what they mean

| Error | Meaning | Action |
|-------|---------|--------|
| `BlockhashNotFound` | Blockhash too old at send time | Rebuild with a fresh blockhash as a *new* journaled action |
| Tx confirmed but `err` set | Landed and failed on-chain | Read logs; it's terminal — do not blindly retry |
| Expired (past `lastValidBlockHeight`) | This tx can never land | Terminal; reconcile, then optionally start a new action |
| `429` on send | RPC rate limit | Back off + failover ([reliability.md](reliability.md)), don't re-sign |
| Repeated timeouts | Likely dropped at the RPC | Rebroadcast same bytes; check provider landing rate |

## Checklist

- [ ] Blockhash captured **with** `lastValidBlockHeight`
- [ ] Simulated before first send; `err` blocks the send
- [ ] CU limit from simulation; CU price from recent fees, capped
- [ ] Confirmed by blockheight expiry, not a sleep/timeout
- [ ] Retries rebroadcast the **same signed bytes** — never re-sign
- [ ] Signature derived up front for the idempotency journal
- [ ] Durable nonce used for anything outside the blockhash window
