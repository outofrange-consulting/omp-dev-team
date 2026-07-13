---
description: Scope the current task (sets the plan gate). Use before planning/building.
argument-hint: "[--trivial | --complex] <task description>"
allowed-tools:
  - Bash
---

Record the size of the task so the plan gate knows whether to require a plan.

Run exactly one of these (based on `$ARGUMENTS`):

- `devteam-gate scope --trivial` — a one-liner / no-risk change; production edits are allowed immediately.
- `devteam-gate scope` — standard task; a plan is required (run `/plan`, then `/plan-approve`).
- `devteam-gate scope --complex` — complex task; a plan is required and should use the deep tier.

Then briefly restate the task and the chosen size, and tell the user the next step (`/plan` unless trivial).
