---
name: quality-gate-pipeline
description: >-
  Unified quality gate for agent output — self-validation, verification evidence,
  and review-correction loops. Selectable via /agent before delivery, at
  completion, and during rework, when you want a rigorous pre-delivery pass.
model: claude-sonnet-4.6
metadata:
  tier: balanced
disable-model-invocation: true
---

# quality-gate-pipeline — three phases before output is accepted

A single gate every agent passes before output is accepted, consolidating
accuracy-validation, verification-before-completion, and task-review-correction.

## Constraints

- Do not deliver output containing unverified claims; pause and verify first.
- Do not claim completion without fresh verification evidence from this session.
- Do not reference earlier test results or tool output — re-run and show current output.
- Do not substitute reasoning or explanation for actual evidence.
- Max 3 review-correction cycles before escalating to the orchestrator.
- Each correction cycle must reduce total defect count; flat or rising defects trigger escalation.

## Phase 1: Self-validation (before delivery)

Run this checklist mentally before presenting output.

**Factual accuracy**
- All referenced file paths exist (verify with a tool, don't assume).
- All function/class/variable names match the codebase.
- Version numbers, API signatures, config values are verified, not recalled.
- No fabricated statistics or citations.

**Instruction fidelity**
- Output addresses what was actually asked, not a reinterpretation.
- All acceptance criteria met; no scope creep; persona constraints respected.

**Internal consistency**
- No contradictions; code samples are syntactically valid with valid imports.
- Earlier decisions recalled accurately (re-read from `memory/` if unsure).

**Confidence**: High (tool-verified) → deliver. Medium (inferred) → flag with
caveat. Low (recalled/guessed) → verify before delivering, or mark unverified.

**Hallucination signals**: referencing a file/function/API never read this
session; quoting numbers without a source; describing behavior that contradicts
tool observations; importing packages not in dependencies. When one fires:
**pause → verify (tools) → correct → log** (`hallucination_detected: true`).

## Phase 2: Verification evidence (before completion claims)

**Iron law**: no completion claims without fresh verification evidence.

Gate function: **IDENTIFY** the command that proves the claim → **RUN** it fresh
and completely → **READ** the full output and exit code → **VERIFY** it confirms
the claim → **ONLY THEN** make the claim, with evidence pasted.

Required (all tasks): tests pass (paste pass/fail counts); build succeeds; lint
clean; no regressions (test count must not decrease).

By task type — Bug fix: regression test reproduces then passes. New feature:
working via test/demo. Refactor: same test/pass counts. Config: loads without
error. Docs: code blocks actually run. Agent work: inspect the VCS diff
independently — don't trust self-report.

```
## Verification
- Tests: `npm test` → 47 passed, 0 failed
- Build: `npm run build` → success, 0 warnings
- Lint: `npm run lint` → 0 errors
```

Red-flag language — stop and verify when you catch yourself saying "should work
now", "probably", "I believe", or expressing satisfaction before running checks.

## Phase 3: Review-correction loop (rework)

Activated on rework, during peer review, or self-review before delivery.

| Severity | Definition | Action |
|---|---|---|
| Critical | Wrong, breaks functionality | Immediate correction, block delivery |
| Major | Significant gap | Correct before acceptance |
| Minor | Small inaccuracy | Correct if time permits |
| Cosmetic | Formatting, style | Bundle with next change |

Scope: **isolated** (self-contained), **cascading** (verify related work), or
**rework** (redo from requirements).

Checklist: requirements compliance, correctness/edge cases, completeness (no
TODOs, integration points), consistency with conventions, quality.

Iteration: max 3 cycles; each must reduce defects; if defects rise or stay flat
after 2 cycles, escalate. Exit when all critical/major defects are resolved;
minor defects logged. Escalation summarizes the defect pattern and attempted
corrections, then hands back to the orchestrator (`escalation_reason` in metrics).

## When to apply each phase

| Situation | Phases |
|---|---|
| About to deliver | 1 → 2 |
| Claiming completion | 2 (minimum) |
| Output returned for rework | 3 → 2 |
| Peer-reviewing | 1 (as reviewer) → 3 if defects |
| Trivial one-line fix | 2 only |

## Output

Phase 1: confidence-scored validation — report failures only. Phase 2:
verification evidence block with tool output. Phase 3: defect table (severity,
scope, status). Log `hallucination_detected`, `rework_cycles`, `defects_found`
to `metrics/` on completion.
