---
name: quick-commit
description: Stage, commit, and summarize changes with a conventional commit message.
---

Create a clean commit for the current changes.

Steps:
1. `git status` and `git diff` to see what changed.
2. Group related changes; if they're unrelated, suggest splitting into multiple commits.
3. Write a conventional-commits message: `type(scope): summary` (`feat`, `fix`, `docs`, `refactor`, `test`, `chore`).
4. **Before committing, scan the diff for secrets** — keys, `.env` values, seed phrases. If anything looks sensitive, STOP and warn.
5. Commit. Do not push unless asked.
