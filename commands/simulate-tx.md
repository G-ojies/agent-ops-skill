---
name: simulate-tx
description: Simulate a Solana transaction and explain the result before any send.
---

Simulate the transaction the user is about to send and report whether it is safe to broadcast. **Never send** as part of this command.

Steps:
1. Build (or take) the signed/compiled transaction and encode it (`getBase64EncodedWireTransaction` for `@solana/kit`).
2. Call `simulateTransaction` with `encoding: 'base64'`, `replaceRecentBlockhash: false`, `sigVerify: true`.
3. Report:
   - **Result**: pass / fail (`err`).
   - **If failed**: the `err`, the key lines from `logs`, and the likely cause (missing account, wrong signer, insufficient funds, program error).
   - **If passed**: `unitsConsumed` and the CU limit you'd set (≈ units × 1.1), plus any writable-account warnings.
4. Recommend: send / don't send / fix-then-resimulate. If `err` is set, the recommendation is always "do not send."

See `skill/transactions.md`.
