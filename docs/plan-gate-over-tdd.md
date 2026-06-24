# Plan-gate over TDD

Replace test-first (TDD) **enforcement** with a **forced plan gate**, and keep
tests as a required quality net. Research indicates RED→GREEN→REFACTOR *ordering*
adds little for AI agents; the leverage is making the agent **and** the human go
through planning before implementing.

## Enforced pipeline

```
pre-analysis (/scope) → (trivial | plan) → build → review
```

The **`plan-gate`** extension (PreToolUse, returns `block: true`) blocks edits to
**production source** until the task is scoped and — if non-trivial — a plan is
approved. It binds both actors: neither the agent nor the human can implement
source before the plan step. Docs, config, `.feature` specs, and tests are
**never** gated.

Commands (state persisted out-of-tree, so `/build` subagents inherit it):

| Command | Effect |
|---|---|
| `/scope` | Pre-analysis: marks the task **needs-a-plan** (stays locked). |
| `/scope --trivial` / `/trivial` | Hybrid bypass: marks the task **trivial** → source unlocked (typo, comment, one-line doc/config, tiny obvious fix). |
| `/plan-approve [path]` | After human sign-off → unlocks the build. Requires the task to be scoped first. |
| `/plan-reset` | Re-arm the gate for the next task. |

Review is enforced at commit by the existing `review-gate` (`/code-review` →
`/review-approve`).

## Tests: required, not test-first

- `tdd-first` rule → **`tests-required`** rule: every behavior change ships with
  tests, written in any order; a unit is done only when `/impl-verify` (strict
  build + tests) is green. Don't edit a failing test to pass; don't weaken gates.
- `test-driven-development` skill → **`testing-discipline`** skill (tests
  required, test-first optional; good-test guidance retained).
- `tdd-guard` extension → **`spec-guard`** (keeps the `.feature` spec-integrity
  block; the RED→GREEN nudge — the only test-first piece — was removed).

## Touched surface

New: `extensions/plan-gate.ts`, `rules/tests-required.md`,
`extensions/spec-guard.ts` (from tdd-guard), `skills/testing-discipline/`
(from test-driven-development). Removed: `extensions/tdd-guard.ts`,
`rules/tdd-first.md`. Rewired: `package.json` (extensions list), orchestrator
(enforced pipeline + Phase 2/3), `/build` + build skill + implementer prompt
(impl-verify gate, not RED-GREEN), `/plan` + plan skill, plan-review prompts,
`dev-team-harness` skill, `help`, both READMEs, manifests (descriptions),
knowledge index + agent-registry (renamed skill).

## Verified
All dev-team extensions compile; unit suite green (incl. plan-gate
`isGatedSource` + stage→decision); `ci-validate-json` 23/23; no dangling
`tdd-guard`/`tdd-first`/`test-driven-development` references; installers carry no
hardcoded extension names.
