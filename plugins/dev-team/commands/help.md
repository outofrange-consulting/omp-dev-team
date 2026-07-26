# /help — list dev-team commands and skills

`read skill://help` and follow it. Summarize:

- **Pipeline** (enforced order): `/scope` (pre-analysis) → `/specs` → `/dt-plan`
  → `/plan-approve` → `/build` → `/code-review` → `/review-approve` → `/pr`
  (`/dt-plan`, not `/plan`: `/plan` is an OMP builtin that toggles plan mode, and
  a plugin command of the same name would be permanently shadowed.)
- **Plan gate**: `/scope [--trivial | --complex]`, `/trivial`,
  `/plan-approve [path]`, `/plan-reset` — source edits are blocked until the task
  is scoped and (if non-trivial) a plan is approved. The recorded scope size also
  sets the per-call `effort` (`trivial`→`lo`, `standard`→`med`, `complex`→`hi`)
  the orchestrator passes to the `task` tool **while planning only**; build and
  review pass nothing and run at each agent's declared floor.
- **Verify**: `/impl-verify` (strict build + tests, bounded verdict)
- **Review**: `/code-review` (`/review`), `/review-agent`, `/review-approve`
- **Guardrails**: `/careful on|off|status`, `/freeze <glob>`, `/unfreeze`,
  `/allow-feature-edits`, `/protect-features`, `/cost-report`
- **Flow**: `/continue`, `/triage`, `/design-doc`, `/issues-from-plan`
- **Everything else**: every ported skill is available as `/skill:<name>`
  (e.g. `/skill:testing-discipline`, `/skill:threat-modeling`,
  `/skill:handoff-policy`). Some skills deliberately have **no** command of the
  same name because OMP owns it — `setup` and `handoff` are builtins.

Arguments: `$ARGUMENTS`.
