# Failure-Class Routing

Read at the start of each repair iteration in `/build` step 4 (the per-behavior
IMPLEMENT → TEST → REFACTOR cycle and its review-fix loop) and `/skill:apply-fixes`
step 4 (per-fix validation). Classify the failing output or exit code **by
regex** — deterministic, no model call, no extra dispatch. Only the route
changes; iteration caps never rise and a route switch never resets the shared
budget.

The point is not the table. The point is that choosing a repair strategy used to
cost a reasoning turn per failure, and now costs a string match. A blind retry
and a diagnosis are indistinguishable to the loop counter, so the loop spends
its budget on retries; classification makes the second failure of the same test
mean something different from the first.

## Classification Table

| Signature pattern | Class | Route | Escalation |
|---|---|---|---|
| `SyntaxError\|error TS\d+\|error CS\d+\|cannot find symbol\|ParseError\|unexpected token`; compiler exit 2 | `compile-syntax` | inline fix | Stays inline on repeat — there is no ambiguity left to diagnose. |
| Named test fails again after one inline attempt; `AssertionError\|expect\(.*\)\.to\|FAILED .*::test_\|Assert\.\w+` | `behavioral-test` | inline fix (1st time) | Same test fails again → `/skill:systematic-debugging`, not another blind retry. |
| `coverage.*below threshold\|Statements.*% \(< \|branch coverage .* below` | `coverage-gap` | test generation — dispatch `qa-engineer`, or `/skill:test-design` when the gap is a whole behavior rather than a branch | Repeats → escalate to the human (the threshold may be miscalibrated). |
| `eslint\|prettier\|black --check\|ruff\|gofmt\|dotnet format` non-zero, style-only diagnostics | `lint-format` | inline fix | Repeats → generic fall-through (at that point it is config, not code). |
| A security-review finding (secrets, injection, auth bypass) surfaces during validation | `security-finding` | `security-engineer` (`/build`: dispatch; `/skill:apply-fixes`: annotate only — it has no `task` grant) | Never downgrades to inline; unresolved after dispatch → human arbitration. |
| Two or more reviewers disagree on the same finding or the same fix | `reviewer-conflict` | human arbitration (the existing escalation: interactive ask; non-interactive hard stop to `memory/build-escalation-<slug>.md`) | Never auto-resolved by picking a side. |
| No pattern matches | `unclassified` | generic loop (fall-through, unchanged) | None — byte-identical to pre-routing behavior. |

## Notes

- **`/build`**: the classification *is* the diagnosis the orchestrator's step-4
  contract already requires before a second attempt — not an added step.
- **Dispatch at the agent's declared floor.** `/build` is post-plan, so it passes
  no per-call `effort:` when it routes to `security-engineer` or `qa-engineer`;
  the agent's frontmatter model role is the floor and the only effort surface
  (`agents/orchestrator.md` § Resolution Procedure). Raising effort here would
  be a second, uncalibrated knob on a path that already has one.
- **`/skill:apply-fixes` never dispatches.** Its `allowed-tools` carries no `task`
  grant, so non-inline routes annotate the Fix Summary with the class and the
  recommended route, then move on. A skill that cannot dispatch must not pretend
  it can.
- **A route switch spends from the same budget.** Moving from inline to
  `systematic-debugging` draws on the same 5-iteration review-fix cap and the
  same 2-correction-iteration checkpoint — it never extends or resets either.
  Otherwise "try a different route" becomes an infinite-loop generator.

## Connections

- The loop this runs inside → `/build` step 4, `/skill:apply-fixes` step 4,
  `agents/orchestrator.md` (review-fix loop, escalation rules).
- The second-failure route → the `systematic-debugging` skill.
- What the run reports afterwards → `skill://dev-team-knowledge/evidence-bundle.md`
  (a classified failure that was escalated is a Residual risk, not a silent pass).
