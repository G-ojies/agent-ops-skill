# Key Custody & Signing

An autonomous agent holds a signing key and uses it without a human in the loop. That key *is* the funds it can move. Custody is therefore the highest-stakes decision in the whole system: get it wrong and a leaked log line or a compromised host drains everything the key can reach. The two governing principles are **least privilege** (the key can only ever reach what it must) and **secrets never leave the process in the clear**.

## Separate the hot key from the treasury

Never let the operational key hold meaningful balance.

```
treasury (cold / multisig)  --tops up-->  hot operational key (small float)  --acts-->
```

- The **hot key** carries only the float it needs for near-term operations plus fees. If it leaks, the blast radius is the float, not the treasury.
- The **treasury** is cold (hardware) or a multisig (e.g. Squads). Top-ups to the hot key are deliberate, rate-limited, and ideally require human/multisig approval.
- Combine with the in-code spend cap and destination allowlist in [safety.md](safety.md): even a fully compromised hot key can't send outside the allowlist if the allowlist is enforced by a separate signer/policy. (Enforcement in the same process the key lives in is a speed bump, not a wall — see below.)

## Where the key lives — choose by stakes

| Storage | Blast radius if host is compromised | Use for |
|---------|-------------------------------------|---------|
| Env var / secret manager | Full key exposure | Low-value hot keys, devnet, early stage |
| Encrypted file + KMS-decrypt at runtime | Key in memory only | Moderate value |
| **Remote signer / KMS / HSM** (key never in app memory) | App can *request* signatures, can't exfiltrate the key | Anything holding real value |
| Multisig / threshold (Squads, MPC) | No single point of compromise | Treasury, high-value actions |

The progression is about *where signing happens*. With a remote signer or HSM, your agent sends an unsigned (or partially signed) transaction to a signing service that holds the key and enforces policy; the host running the agent never sees the private key, so a host compromise can't steal it — only abuse it within the signer's policy limits. That last clause is why the signer should enforce the spend cap and allowlist itself.

## Never log, never serialize, never transmit secrets

This is the most common real-world leak: a private key or seed ending up in a log, a heartbeat, a crash dump, or an error message.

```ts
// Redact at the boundary. Treat key material as a tainted type.
const REDACT = /(?:[1-9A-HJ-NP-Za-km-z]{43,88}|\b[0-9a-f]{64}\b)/g;  // base58 secrets / hex
function safeLog(obj) {
  return JSON.stringify(obj).replace(REDACT, '[REDACTED]');
}
```

Hard rules:
- Secrets come from `process.env` / a secret manager and are read **once** into memory. Never written back to disk, never put in config that gets committed (the `.gitignore` already blocks `*-keypair.json`, `.env`, `id.json`).
- Error objects can carry context that includes a key — redact before logging, and never `console.log(error)` raw on a path that handled key material.
- Heartbeats, alerts, and audit-trail entries ([observability.md](observability.md)) go through the same redaction.
- In CI, secrets are masked job secrets, never echoed.

## Signing discipline

- **Sign the minimum.** Build the exact instructions, simulate ([transactions.md](transactions.md)), then sign. Don't pre-sign blank or broad authorizations.
- **One signer object, scoped.** Load the keypair into a single signer used by the send path; don't pass raw secret bytes around the codebase.
- **Durable-nonce / offline transactions are live liabilities.** A signed-but-unsent transaction can be submitted by anyone who gets the bytes — store them as carefully as the key, and journal them.
- **Rotate on suspicion.** Have a documented rotation path: generate a new hot key, repoint the agent, drain the old one. Rotation should be a runbook, not an emergency improvisation.

## Compromise response (write this before you need it)

1. Trigger the kill switch ([safety.md](safety.md)) — stop the loop.
2. Drain the hot key to the treasury.
3. Rotate to a new hot key; invalidate the old secret everywhere it was stored.
4. Review the audit trail ([observability.md](observability.md)) for unauthorized actions.

## Checklist

- [ ] Hot operational key separate from treasury; only a small float
- [ ] Storage tier matches the value at risk (KMS/remote signer for real value)
- [ ] Spend cap + allowlist enforced by the signer/policy layer, not just app config
- [ ] Redaction at every log/heartbeat/alert boundary; secrets never serialized
- [ ] Secrets only from env/secret manager; key files gitignored
- [ ] Signed-but-unsent (nonce/offline) txs treated as secrets and journaled
- [ ] Documented rotation + compromise runbook
