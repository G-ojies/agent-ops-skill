---
name: safety-review
description: Run the pre-launch guardrail and key-custody checklist against the agent codebase.
---

Run an adversarial pre-launch safety review of the current agent codebase. Invoke the **safety-reviewer** agent and work through its checklist.

Cover:
- **Guardrails**: allowlist + per-tx + window + per-tick caps enforced in code between DECIDE and ACT; dry-run default; approval gate; kill switch; circuit breaker.
- **Key custody**: hot key separate from treasury; storage tier vs value; secrets never logged/serialized; key files gitignored.
- **Correctness**: idempotency (intent journaled before send, startup reconciliation); retries rebroadcast same bytes (never re-sign); confirmation by blockheight; money verified at `finalized`.
- **Input trust**: LLM/oracle/external inputs pass through `guard()`; oracle reads sanity-checked.

For each finding give: severity (blocker/high/advisory), `file:line`, worst-case loss if shipped, and the fix. End with a single verdict: **SHIP** or **DO NOT SHIP** + blocker count. Missing kill switch or spend cap = automatic DO NOT SHIP.

See `skill/safety.md`, `skill/key-custody.md`, `agents/safety-reviewer.md`.
