# Test Automation Principles

What an automated suite is *for*, and the principles that keep it valuable. A
rubric for `test-review` / `test-smell-review` and for designing a suite.
Adapted from *xUnit Test Patterns* (Meszaros). **A suite that is green but not
Repeatable or Robust is a liability, not an asset.**

## Goals (what the suite buys you)

| Goal | Failure mode if absent |
|---|---|
| Tests as **Specification** | behavior is undocumented; nobody knows what's intended |
| Tests as **Documentation** | readers can't learn the API from the tests |
| **Defect Localization** | a failure doesn't say *where* the bug is |
| **Bug Repellent** | regressions slip through |
| **Fully Automated** | needs a human to run/interpret → skipped under pressure |
| **Self-Checking** | "didn't crash" passes for "correct" |
| **Repeatable** | flaky; green/red depends on order, clock, network |
| **Robust** | breaks on unrelated changes (over-specified) |
| **Simple / Expressive** | too costly to write, so people don't |

## Principles (rule → remedy)

- **Design for Testability** — untestable code is a production-code smell; fix
  the code (Humble Object), not the test.
- **Use the Front Door First** — exercise the public API; back-door manipulation
  couples the test to internals.
- **Communicate Intent** — ≤ ~10 lines of logic per test; name the scenario.
- **Don't Modify the SUT** for the test's convenience; **Keep Test Logic Out of
  Production**.
- **Keep Tests Independent** / **Isolate the SUT** — no shared mutable state, no
  ordering dependence.
- **Minimize Test Overlap** — each behavior covered once, at the right level.
- **Verify One Condition per Test**; **Test Concerns Separately**.
- **Ensure Commensurate Effort** — test effort ≤ the feature's effort; if a test
  is far harder than the code, the design is telling you something.

## Using this as a rubric

1. Name the at-risk **goals** (served / weak / absent).
2. Trace each to a violated **principle**.
3. Locate the remedy in the supporting docs.

Severity order: **Can't-fail / Can't-trust** (Buggy, Erratic) > **Hard to
read/maintain** (Obscure, Fragile) > stylistic.

## Connections

`test-smells.md` (the smells), `testability-patterns.md` (production-code fixes),
`fixture-construction.md` + `value-patterns.md` (data), `result-verification.md`
(assertions), `legacy-test-strategy.md` (where to test legacy code).
