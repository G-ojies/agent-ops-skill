# Resources

Curated, current-to-2026 references for building and operating autonomous Solana agents. Prefer primary docs over blog posts; verify versions against what's actually installed.

## SDKs

- **@solana/kit** (web3.js v2) — the default client. Transaction building, signing, RPC, subscriptions. https://github.com/anza-xyz/kit
- **@solana-program/compute-budget** — priority fees & compute-unit limits as instructions.
- **@solana-program/system**, **@solana-program/token** — system + SPL token program clients for kit.
- **@solana/web3.js v1** — legacy; use only where a dependency requires it. Mind the v1↔v2 interop boundary.
- **solana-py + solders** — Python client + fast Rust-backed primitives, for Python agents.
- **Anchor / Codama** — IDL and typed client generation → see core skill [idl-codegen.md](../solana-dev/idl-codegen.md).

## RPC providers

- **Helius** — RPC, enhanced APIs, webhooks, staked-connection sending. Strong for indexing + landing.
- **Triton One** — low-latency RPC, Geyser/Yellowstone gRPC streaming.
- **QuickNode** — RPC + add-ons.
- **Public mainnet RPC** — last-resort fallback only; heavily rate-limited, not for production sends.
- Always run **≥2 providers** with health checks ([reliability.md](reliability.md)).

## Transaction landing & MEV

- **Jito** — block engine, bundles (atomic, all-or-nothing), tips for inclusion. For multi-tx atomic actions and congested-network landing.
- **Priority fees** — `getRecentPrioritizationFees` + `ComputeBudgetProgram`; size to a percentile, cap it ([transactions.md](transactions.md)).
- **Durable nonces** — for signing outside the blockhash window.

## Streaming & indexing

- **Yellowstone gRPC (Geyser)** — high-throughput account/transaction streaming.
- **Helius webhooks** — push-based event delivery (dedupe + verify signatures).
- **WebSocket subscriptions** — `accountSubscribe` / `logsSubscribe`, always with a polling backstop ([architecture.md](architecture.md)).

## Testing

- **LiteSVM** — fast in-process SVM for deterministic transaction/program tests.
- **Mollusk**, **Surfpool** — see core skill [testing.md](../solana-dev/testing.md).
- **Devnet** + faucet — full-loop integration before mainnet.

## Key custody

- **Squads** — multisig / smart accounts for treasury and high-value actions.
- **KMS / HSM / remote signers** — keep keys out of app memory for real value ([key-custody.md](key-custody.md)).
- **Turnkey / Privy / Web3Auth** — managed/embedded signing options to evaluate by stakes.

## Standards

- **Solana Pay** — reference-keyed transfers; clean payment reconciliation ([payouts.md](payouts.md)).
- **SPL Memo** — attach references for matching.

## Official docs

- Solana Docs — https://solana.com/docs
- Anza (validator/SDK) — https://github.com/anza-xyz
- Solana Cookbook — practical recipes (verify against current SDK versions)

> Versions move fast. Before relying on a snippet, check the installed package version and the provider's current limits — this skill targets the 2026 stack and `@solana/kit` as the default.
