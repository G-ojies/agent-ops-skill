# Payouts, Claims & Reconciliation

Many agents exist to *receive* value (a bounty payout, a reward, a fee rebate, a swap output) or to *disburse* it. This is the side where being wrong is most expensive and least reversible, so the standard is higher than for ordinary actions: **verify against finality, reconcile against your own records, and never trust a status field over the chain.**

## Verify money at `finalized`, never `processed`/`confirmed`

For anything money-final, confirm at `finalized` ([reliability.md](reliability.md)). A `confirmed` transfer can — rarely — be rolled back; if you credit a user or advance your accounting on a `confirmed` read that later disappears, you've created a phantom balance.

```ts
// Verify an inbound payout actually landed and is final, by inspecting the chain — not an API's word.
async function verifyInbound({ expectedTo, expectedAmount, reference }) {
  const sigs = await rpc.getSignaturesForAddress(expectedTo, { limit: 25 }).send();
  for (const { signature } of sigs) {
    const tx = await rpc.getTransaction(signature, {
      commitment: 'finalized', maxSupportedTransactionVersion: 0,
    }).send();
    if (!tx || tx.meta?.err) continue;
    const delta = balanceDelta(tx, expectedTo);            // from pre/postBalances or token balances
    if (delta >= expectedAmount && matchesReference(tx, reference)) {
      return { verified: true, signature, slot: tx.slot };
    }
  }
  return { verified: false };
}
```

The point is that *verification reads the chain*. An off-chain "payout sent" webhook or status field is a hint to go check, never the proof.

## Tie every payout to a reference

To reconcile, each expected payment needs a deterministic link between your record and the on-chain event:
- **Memo / reference pubkey** (Solana Pay style) — the cleanest: you generate a reference, expect it on the transfer, and match exactly.
- **Exact amount + counterparty + time window** — workable when you control the amount, weaker when amounts collide.
- **Your own outbound signature** — for disbursements, the signature you got at send time *is* the reference; store it and reconcile against it.

Match on the reference first; fall back to amount/counterparty only when no reference is possible, and flag those for human review.

## Disbursing: idempotent, capped, allowlisted

Paying out is just an action — so it inherits everything from [transactions.md](transactions.md) and [safety.md](safety.md):
- **Idempotent**: each payout keyed by a deterministic id so a retry/restart can't pay twice. This is the double-spend rule applied to money you're sending out — the most expensive place to get it wrong.
- **Allowlisted destinations + caps** ([safety.md](safety.md)) — a bug in recipient resolution must not be able to send to an arbitrary address.
- **Verify after send** at `finalized`, then mark the payout `settled` in the ledger.

## Reconciliation loop

Run a periodic reconciliation independent of the action loop: walk your ledger of `expected`/`pending` items and verify each against the chain.

```
for each ledger entry not 'settled':
  result = verify on-chain at finalized
  if verified:  mark settled, record signature+slot
  if past deadline and still unverified:  flag for human (missing payout / failed disbursement)
```

Reconciliation is what catches the gaps the happy path misses: a payout that the counterparty *says* they sent but didn't, a disbursement that failed silently, a duplicate credit. It is also where your audit trail ([observability.md](observability.md)) earns its keep — every settled entry carries the signature that proves it.

## Claim flows (agent-initiated claims)

When the agent claims a reward/airdrop:
1. Confirm eligibility from authoritative on-chain state, not a UI.
2. Build + simulate the claim ([transactions.md](transactions.md)); a claim that simulates to `err` (already claimed, not eligible) must not be sent.
3. Journal the claim with its deterministic id so it's claimed exactly once.
4. Verify receipt at `finalized` and reconcile.

## Checklist

- [ ] Money verified at `finalized`, read from the chain — not a status field
- [ ] Every expected payment tied to a reference (memo/pubkey/signature)
- [ ] Disbursements idempotent, capped, allowlisted
- [ ] Independent reconciliation loop flags unverified items past deadline
- [ ] Claims simulated first; `err` (already claimed) blocks the send
- [ ] Settled entries carry the on-chain signature in the audit trail
