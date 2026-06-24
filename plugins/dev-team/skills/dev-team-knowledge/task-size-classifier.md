# Task Size Classifier

Objective classifier for the **pre-analysis (`/scope`)** step of the plan gate.
It decides — from **objective signals only, never a fresh LLM judgement** —
whether a task is `trivial`, `standard`, or `complex`. `trivial` takes the
**no-plan fast path**; the rest go through the full Research → Plan → Build
pipeline. This makes the `/scope --trivial` decision principled (not vibes) and
saves tokens on small work.

## Signals (estimate before implementation; measure after)

- `files_changed` — distinct files the change will touch
- `loc_delta` — lines added + removed
- `slice_count` — vertical slices the plan would have
- `wave_count` — parallel build waves (`Depends-on` groups)
- `has_complex_step` — any step needing non-trivial design/algorithm
- `decision_axis_triggered` — a choice only the human can make (API/schema/
  security/cross-cutting/third-party-library), or a security-sensitive surface

## Tiers

**`trivial` — no-plan fast path.** ALL must hold:

| Signal | Threshold |
|---|---|
| `files_changed` | ≤ 1 |
| `loc_delta` | ≤ 50 |
| `slice_count` | ≤ 1 |
| `wave_count` | ≤ 1 |
| `has_complex_step` | false |
| `decision_axis_triggered` | false |

**`complex`.** ANY of:

| Signal | Threshold |
|---|---|
| `files_changed` | ≥ 6 |
| `loc_delta` | ≥ 300 |
| `wave_count` | ≥ 2 |
| `has_complex_step` | true |
| `decision_axis_triggered` | true |
| security-sensitive or cross-cutting | yes |

**`standard`.** Everything between trivial and complex.

**Bias rule.** When signals are ambiguous or missing, **classify up** (standard
over trivial, complex over standard) — underestimating complexity costs more
rework than the saved ceremony.

## What each tier triggers (mapped to the plan gate)

- **`trivial` → `/scope --trivial`** (fast path). Skips the design doc, the
  Research/Plan ceremony, the five plan-review personas, wave scheduling, and
  the plan human gate. Goes straight to implementation. **Quality gates are NOT
  removed:** tests are still required and verified by `/impl-verify`, the inline
  review runs, and `/code-review` → `/review-approve` still gate the commit.
- **`standard` → `/scope`** (needs-plan). Full Research → Plan → Build with the
  plan human gate and `/plan-approve` before any source edit.
- **`complex` → `/scope`** (needs-plan), plus the orchestrator escalates review
  depth to the opus-tier agents (security-review, domain-review, arch-review).

Expected saving on small tasks (upstream measurement): **~65% fewer turns,
~45% lower cost** vs the full pipeline.

## Decision logging

Record each classification in `memory/decisions.md`: the signal values, the
resulting tier, and a one-line rationale. This keeps the fast-path decision
auditable and lets the learning loop catch mis-classifications (a "trivial" task
that needed three fix rounds was misclassified — tighten the estimate next time).
