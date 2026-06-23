# Testing Autonomous Agents

You cannot supervise an agent in production — so you have to earn confidence before it goes live. The test strategy mirrors the loop: **pure decision logic gets unit tests, every transaction path gets simulated, failures get injected on purpose, and the whole loop gets a devnet dry-run before a mainnet key ever loads.** For on-chain program testing (LiteSVM, Mollusk, Surfpool), delegate to the core skill's [testing.md](../solana-dev/testing.md); this file is about testing the *agent*.

## 1. Unit-test the DECIDE function (it's pure, so this is easy)

Because DECIDE is a pure `state -> actions` function ([architecture.md](architecture.md)), you can test the agent's judgment with zero network.

```ts
test('skips action when balance below reserve', () => {
  const actions = decide({ ...baseState, hotBalance: 100n, reserve: 1000n });
  expect(actions).toHaveLength(0);
});

test('never proposes an action over the per-tx cap', () => {
  const actions = decide(stateWithHugeOpportunity);
  expect(actions.every(a => a.lamports <= MAX_PER_TX)).toBe(true);
});
```

Cover the edge cases that cause real losses: empty/low balance, conflicting signals, stale cursor, an opportunity that exceeds caps, malformed external input.

## 2. Test guards independently

The `guard()` function from [safety.md](safety.md) is your last line of defense — test that it actually blocks.

```ts
test('blocks non-allowlisted destination', () => {
  expect(() => guard({ destination: ATTACKER, lamports: 1n }, state)).toThrow('not allowlisted');
});
test('window cap stops the Nth action', () => { /* fill the window, assert the next throws */ });
```

## 3. Simulate every transaction path

Before any send path is trusted, run its transaction through `simulateTransaction` (or LiteSVM for richer program assertions). This catches a malformed instruction, a missing account, or a wrong signer without spending anything.

```ts
test('claim tx simulates cleanly', async () => {
  const sim = await rpc.simulateTransaction(buildClaimWire(fixture), { encoding: 'base64' }).send();
  expect(sim.value.err).toBeNull();
});
```

For deterministic, fast, offline transaction tests, **LiteSVM** lets you load accounts and execute instructions in-process — ideal for asserting exact balance deltas and program logs without a validator.

## 4. Inject failures — the part most agents never test

Production *will* deliver 429s, timeouts, expired blockhashes, and disagreeing providers. Mock the RPC and assert the agent does the right thing.

```ts
test('rebroadcasts same bytes, never re-signs', async () => {
  const rpc = mockRpc({ sendTransaction: failTwiceThenSucceed() });
  const spy = jest.spyOn(signer, 'sign');
  await execute(action, rpc);
  expect(spy).toHaveBeenCalledTimes(1);   // signed once, rebroadcast many — the cardinal rule
});

test('treats expired blockhash as terminal, not infinite retry', async () => {
  const rpc = mockRpc({ getBlockHeight: aboveLastValid(), getSignatureStatuses: neverConfirms() });
  await expect(execute(action, rpc)).rejects.toThrow(BlockhashExpired);
});

test('idempotent across crash', async () => {
  await execute(action);                  // completes, journals done
  const spy = jest.spyOn(rpc, 'sendTransaction');
  await execute(action);                  // replay same actionId
  expect(spy).not.toHaveBeenCalled();     // no second send
});
```

The three tests above map to the three most expensive bugs: re-signing on retry (double-spend), infinite retry on a dead tx (wasted fees / stuck loop), and non-idempotent replay (double-spend on restart). If you test nothing else here, test these.

## 5. Devnet dry-run of the whole loop

Before mainnet, run the **full loop on devnet** — real RPC, real sends, throwaway keys, tiny amounts. This exercises the integration the unit tests mock: actual blockhash expiry timing, actual confirmation latency, actual provider behavior.

Then the staged rollout from [safety.md](safety.md): dry-run on mainnet (sends disabled) → mainnet live with minimal caps → raise caps as confidence grows. The mainnet **dry-run** (`/agent-dry-run`) is special: it runs the real decision loop against real mainnet state and prints every action it *would* take — the highest-fidelity test that doesn't risk a cent.

## 6. Replay from the audit trail

Because the audit trail ([observability.md](observability.md)) records intents and outcomes, you can replay a past run through the current DECIDE logic to check a change didn't alter behavior on real historical state — a regression test built from production data.

## Checklist

- [ ] DECIDE unit-tested across edge cases, no network
- [ ] `guard()` tested to actually block (allowlist, every cap)
- [ ] Every transaction path simulated (rpc sim or LiteSVM)
- [ ] Failure injection: 429, timeout, expired blockhash, provider disagreement
- [ ] The three cardinal tests: rebroadcast-not-resign, expiry-terminal, idempotent-replay
- [ ] Full loop dry-run on devnet with throwaway keys before mainnet
- [ ] Mainnet dry-run before live; caps raised gradually
