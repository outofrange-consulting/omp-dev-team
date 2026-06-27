---
description: Deterministic build+test gate — detects the stack, runs a strict build and tests, returns PASS/FAIL/HALT.
argument-hint: "[--skip-tests]"
allowed-tools:
  - Bash
---

Run the deterministic verification gate before claiming a unit of work done:

```
devteam-impl-verify $ARGUMENTS
```

Act on the verdict:
- **PASS** → proceed.
- **FAIL** → fix the root cause and re-run. Never silence the gate (no `eslint-disable`, `# noqa`, `@ts-ignore`, `--no-warnaserror`) — see the `no-disable-analyzers` rule.
- **HALT** → escalate to the human (stack not detected or fix budget exhausted).

Paste the verdict as evidence. Configure stacks/commands in `.dev-team.json` under `implVerify`.
