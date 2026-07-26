# Evidence Bundle

A structured "what was checked, and what wasn't" statement carried by `/build`'s
final output and `/pr`'s PR body. Verification here is a stack of scoped
verifiers — `/impl-verify`'s strict build + tests, the full suite, type check,
lint, the review agents, the Farley score — not one boolean. A green checkmark
alone over-claims: it says checks passed, but not what each one actually
verified, what it structurally *cannot* verify for this diff, which regions
remain untested, or what risk was consciously accepted. The bundle closes that
gap.

This is the reporting counterpart of `/impl-verify`'s verdict-as-evidence rule:
a claim is worth what its pasted evidence is worth, and "not measured" is a
legitimate, informative value.

**Reporting only — no new checks.** The bundle is assembled entirely from data
the pipeline has already produced: the gate outputs of the run itself, the
`/impl-verify` verdicts already pasted as step evidence, the review agents'
`status` fields, the gate-bypass audit lines, and whatever coverage artifact the
repo's own tooling emitted. Assembling it never re-runs a check and never invokes
a tool "just to build the bundle". If assembling the bundle would cost a tool
call, the honest value is "not measured" with the reason.

Reference form in a prompt: `skill://dev-team-knowledge/evidence-bundle.md`.

## The four fixed sections

Always present, in this order, with these exact headers. **Degradation rule**:
when a section has no data, it states why (e.g. "not measured — no coverage tool
detected") — it is never dropped. All four headers appear even on a run with
nothing to report in one of them, because a missing header is indistinguishable
from a check that was silently skipped.

| Section | Content | Data source (already produced) |
|---|---|---|
| Checks run | One row per verifier: the exact command executed + a result summary | `/pr` step 2 gate commands and their output; `/build` step 5 full-suite output, step 6 `/code-review` status, and each step's pasted `/impl-verify` verdict |
| Scope notes | What the executed suite does NOT verify for this diff | Review agents dispatched vs. skipped (a `status: "skip"` finding *is* a scope note); gate steps reported "not applicable"; absent tools (coverage, mutation, browser verification skipped for no dev server) |
| Untested regions | Coverage-derived statement of what the diff leaves unexercised | Whatever coverage report the repo's own test command emitted; the `test-health` skill's coverage view when it ran this session; `mutation-testing` results on critical-logic modules. **"not measured" when none exists** — this port ships no coverage-baseline/coverage-delta pair, so a repo with no coverage tooling of its own has nothing here and must say so |
| Residual risks | Consciously accepted risk, derived first | Deferred / escalated findings from the review-fix loop; `ACCEPTED-RISKS.md` suppressions applied this run; gate-bypass audit lines (`review-gate-bypass.jsonl` in the dev-team state dir — written whenever a commit used `--no-verify` with `GATE_BYPASS_REASON`); structural-review waivers. Author-judged prose may be appended but never substitutes for the derived rows |

## Skeleton

```markdown
## Evidence Bundle

**Checks run**
- `<exact command>` — <result summary>
- `<exact command>` — <result summary>
(N checks total; showing top N — see full log at <pointer> if truncated)

**Scope notes**
- <what this suite does not cover for this diff, one line each>

**Untested regions**
- <coverage figure, or the uncovered files in the diff, or "not measured — <reason>">

**Residual risks**
- <deferred/escalated finding, suppression, waiver, or bypass line — or "None identified" only when every derived source is empty>
```

## Degradation examples

- No coverage tool detected:
  `Untested regions: not measured — no coverage tool detected in this repo.`
  paired with a matching scope note:
  `Scope notes: coverage delta unavailable — this repo emits no coverage report.`
- No deferred or escalated findings, no suppressions, no bypass lines:
  `Residual risks: None identified — no deferred findings, accepted risks, or gate bypasses this run.`
- A bypass recorded during the run: fold the audit line in verbatim, e.g.
  `Residual risks: review gate bypassed with --no-verify — reason: "hotfix, review to follow" (recorded 2026-07-26T14:02Z).`
- A review agent skipped: `Scope notes: a11y-review skipped — no UI files in the changeset.`

## Line budget

Target **under ~40 lines** in a PR body. When a section's data would exceed that,
collapse to counts plus a pointer to the full log rather than growing unbounded —
e.g. `12 checks run, 12 passed (full command log in the build output above)`
instead of listing all 12 rows. A bundle nobody reads verifies nothing.

## Assembly is per-command, not handed off

`/build` assembles its bundle from its own run's step 5/6 outputs and the
`/impl-verify` verdicts pasted during step 4. `/pr` assembles its bundle from its
own step 2 quality-gate results plus on-disk data at its own runtime — **never**
from a handoff file written by `/build`. Running `/pr` standalone (no preceding
`/build` in the session) still produces a complete bundle; sections degrade per
the rule above wherever the on-disk data doesn't cover a source that only
`/build`'s in-session steps would have (the per-step `/impl-verify` verdicts, the
Farley score from `test-design-reviewer`).

## Boundaries

- **Does not persist.** Every underlying datum already persists in its own source
  file (the gate state and bypass log in the dev-team state dir, the plan file's
  Build Progress section, the repo's own coverage artifact). A persisted bundle
  would fork that audit trail and immediately start drifting from it.
- `/code-review`'s own report keeps its existing contract
  (`skill://dev-team-knowledge/review-template.md`); it is one **input** to the
  Checks run section, not a carrier of the bundle.
- Never displaces the PR body's closing keywords (`Closes #N` / `Part of #`) or
  its existing sections (`## Summary`, `## Quality Gate`, `## Test Plan`) — the
  bundle is added alongside them. `## Quality Gate` stays the checklist; the
  bundle is what the checklist does not say.

## Connections

- The verdict this reports on → the `impl-verify` extension (bounded PASS /
  FAIL / HALT), `/build` step 4.
- Why a check was routed the way it was →
  `skill://dev-team-knowledge/failure-routing.md`.
- The report contract for the review half → `review-template.md`,
  `review-output-discipline.md`.
- Accepted risk that shows up as a Residual risk row →
  `accepted-risks-schema.md`.
