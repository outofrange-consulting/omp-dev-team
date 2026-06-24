# /help — list dev-team commands and skills

`read skill://help` and follow it. Summarize:

- **Pipeline** (enforced order): `/scope` (pre-analysis) → `/specs` → `/plan` →
  `/plan-approve` → `/build` → `/code-review` → `/review-approve` → `/pr`
- **Plan gate**: `/scope [--trivial]`, `/trivial`, `/plan-approve [path]`,
  `/plan-reset` — source edits are blocked until the task is scoped and (if
  non-trivial) a plan is approved.
- **Verify**: `/impl-verify` (strict build + tests, bounded verdict)
- **Review**: `/code-review` (`/review`), `/review-agent`, `/review-approve`
- **Guardrails**: `/careful on|off`, `/freeze <glob>`, `/unfreeze`,
  `/allow-feature-edits`, `/protect-features`, `/routing`, `/cost-report`
- **Flow**: `/continue`, `/triage`, `/design-doc`, `/issues-from-plan`
- **Diagnostics**: `/model-routing-check`, `/routing`
- **Everything else**: every ported skill is available as `/skill:<name>`
  (e.g. `/skill:testing-discipline`, `/skill:threat-modeling`).

Arguments: `$ARGUMENTS`.
