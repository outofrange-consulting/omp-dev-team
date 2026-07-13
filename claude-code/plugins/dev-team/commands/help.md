---
description: List the dev-team commands and how the workflow/gates fit together.
---

# /help — dev-team commands and skills

Summarize for the user:

- **Pipeline**: `/scope` → `/specs` → `/plan` → `/plan-approve` → `/build` →
  `/code-review` → `/review-approve` → `/pr`
- **Plan gate (advisory)**: `/scope [--trivial | --complex]`, `/plan-approve`,
  `/plan-reset` — editing production source before scope/plan prompts for
  confirmation (it asks, it doesn't hard-block).
- **Review gate (blocking)**: `/review-approve` content-approves the staged diff;
  `git commit` is denied until it matches (any later edit re-locks it). `/code-review`
  runs the reviewers; `/review-agent` runs one named reviewer.
- **Verify**: `/impl-verify` (strict build + tests, PASS/FAIL/HALT verdict).
- **Scope control**: the `/dev-team:scope-control` skill — careful mode
  (`devteam-gate careful on|off`) + freeze/guard working agreements.
- **Task metrics**: the `/dev-team:task-metrics` skill — cost, telemetry, and
  end-of-task completion logging.
- **Flow**: `/continue`, `/triage`, `/design-doc`, `/issues-from-plan`.
- **Everything else**: every skill is available as `/dev-team:<name>`
  (e.g. `/dev-team:testing-discipline`, `/dev-team:threat-modeling`,
  `/dev-team:design-techniques`).

Arguments: `$ARGUMENTS`.
