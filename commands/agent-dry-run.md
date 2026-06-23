---
name: agent-dry-run
description: Run the agent's full control loop with sends disabled, showing every action it would take.
---

Run the agent end-to-end in **dry-run mode** (no real sends) and report exactly what it *would* do. This is the highest-fidelity test that doesn't risk funds.

Steps:
1. Ensure live mode is OFF (no `--yes` / `AGENT_LIVE=1`). If you cannot confirm sends are disabled, STOP and ask.
2. Run one full loop: PERCEIVE (real reads) → DECIDE → GUARD → ACT (simulate only).
3. For each intended action, print: the action id, what it would do, the destination, the amount, which guard checks it passed, and the simulation result.
4. Summarize: actions proposed, actions blocked by guards (and why), total would-be spend vs the window cap, any simulation failures.
5. Flag anything that would have sent to a non-allowlisted destination or exceeded a cap as a **blocker** to investigate before going live.

See `skill/safety.md` and `skill/testing.md`.
