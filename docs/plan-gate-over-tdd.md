# Plan-gate over TDD

Replace test-first (TDD) **enforcement** with a **forced plan gate**, and keep
tests as a required quality net. The leverage is making the agent **and** the
human go through planning before implementing.

## Why not enforce RED→GREEN→REFACTOR

This used to read "research indicates ordering adds little for AI agents" and
named no instrument — exactly the unfalsifiable claim our own
`token-efficiency-review` rubric rejects. The honest justification is upstream's,
and it is stronger, so we adopted it wholesale.

ADT ADR-0017 removed classic TDD as an opt-in on a **measured cost result, not a
quality gap**:

| cadence | cost/cell | quality | quality per dollar |
|---|---|---|---|
| **Code-First Small Batches** | **$0.99** | 0.961 | **0.968** |
| Classic TDD | $1.59 | 0.966 | 0.608 |

Classic TDD scored *marginally higher* on quality (0.966 vs 0.961) and cost
**61% more** to get there — 0.608 quality-per-dollar against 0.968. So the
argument against enforcing the ordering is not "it doesn't work"; it is "it is
not worth 61% more per cell for half a point of quality, and the money buys more
elsewhere — namely a plan gate the ordering cannot substitute for."

Two consequences we hold to:

- **The refactor step is not optional.** Dropping test-first is not dropping
  REFACTOR. Code-First Small Batches is IMPLEMENT → TEST → REFACTOR **on every
  green**, with tests frozen during REFACTOR. That is what the $0.99 column
  measured; skipping the refactor is a different cadence with no measurement
  behind it.
- **This is a cost claim, so it expires.** It is a relative-price result on one
  model mix. Re-run the comparison before citing it as a quality argument, and
  re-run it if the price ratio between the tiers moves materially.

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

## Tests: required, in the Code-First Small Batches cadence

- `tdd-first` rule → **`tests-required`** rule: every behavior change ships with
  tests; a unit is done only when `/impl-verify` (strict build + tests) is green.
  Don't edit a failing test to pass; don't weaken gates.
- `test-driven-development` skill → **`testing-discipline`** skill (the cadence
  and the good-test guidance; the RED-first mandate dropped).
- `tdd-guard` extension → **`spec-guard`** (keeps the `.feature` spec-integrity
  block; the RED→GREEN nudge — the only test-first piece — was removed).

## Touched surface

New: `extensions/plan-gate.ts`, `rules/tests-required.md`,
`extensions/spec-guard.ts` (from tdd-guard), `skills/testing-discipline/`
(from test-driven-development). Removed: `extensions/tdd-guard.ts`,
`rules/tdd-first.md`. Rewired: `package.json` (extensions list), orchestrator
(enforced pipeline + Phase 2/3), `/build` + build skill (impl-verify gate, not
RED-GREEN — the implementer prompt has since been folded into the build skill and
deleted per ADR-0029), `/plan` + plan skill, plan-review prompts,
`dev-team-harness` skill, `help`, both READMEs, manifests (descriptions),
knowledge index + agent-registry (renamed skill).

## Verified
All dev-team extensions compile; unit suite green (incl. plan-gate
`isGatedSource` + stage→decision); `ci-validate-json` 23/23; no dangling
`tdd-guard`/`tdd-first`/`test-driven-development` references; installers carry no
hardcoded extension names.
