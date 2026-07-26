# Continuous Delivery Maturity Model

Reference for assessing and improving an organization's delivery capability.
Source: *Continuous Delivery* (Humble & Farley) Ch. 15. Use it to locate where a
team is, pick the one area worth improving next, and define the outcome that
proves the improvement landed. Read by the `platform-engineer` and `architect`
agents when assessing a repo's delivery health, and by `/dt-plan` when a platform
improvement is the deliverable.

This measures **delivery capability** — can this team release small changes
safely and often? That is a *different axis* from how ready a repo is for
AI-agent work (dependency freshness, script determinism, docs an agent can
follow). A repo can score high on one and low on the other; assess them
separately and never average them into one number.

## The six practice areas

Maturity is read per area, not as a single grade — a team is almost always
uneven, and the uneven part is the actionable part.

| Practice area | What it covers |
|---------------|----------------|
| **Build management & CI** | Build automation, trunk-based CI, fast feedback, build discipline |
| **Environments & deployment** | Automated provisioning, identical deploy everywhere, release strategies, rollback |
| **Release management & compliance** | Change/approval flow, traceability, audit through the pipeline |
| **Testing** | Automated test strategy across the pyramid, deterministic gates |
| **Data management** | Scripted, versioned, reversible migrations; managed test data |
| **Configuration management** | Everything in version control; config per environment; secrets handling |

## The five levels

| Level | Name | Signal |
|-------|------|--------|
| **3** | Optimizing | Teams continuously improve the process; cycle time and stability are measured and trending |
| **2** | Quantitatively managed | Process metrics gathered and used to make decisions; risk understood and bounded |
| **1** | Consistent | Automated processes applied across the whole lifecycle, used by everyone |
| **0** | Repeatable | Process documented and partly automated; results repeatable |
| **−1** | Regressive | Processes ad hoc, manual, unrepeatable; results unpredictable; knowledge is tribal |

Score each of the six areas against the five levels to get a **profile**, not a
grade. The lowest areas dominate real cycle time, which is why the profile is the
useful artifact and the average is not.

## How to improve (the Deming cycle)

1. **Map the value stream** — commit to release — and find the most painful or
   slowest area. Improve *that*, not everything at once.
2. **Define acceptance criteria** for the improvement: a measurable outcome, not
   "improve CI".
3. **Implement** the smallest change that moves the area up one level.
4. **Measure** against the criteria, **retrospect**, and roll the change out
   incrementally. Then repeat on the next constraint. Never try to jump all six
   areas to the top level at once.

## The outcomes to target

The model is a means; these are the ends. Track them directly — a level that
moved with no movement here did not actually land.

| Metric | What it tells you |
|--------|-------------------|
| **Cycle time** (commit → releasable) | The primary global signal; the Theory-of-Constraints lens for finding the bottleneck |
| **Deployment frequency** | How small and frequent changes really are |
| **Change failure rate** | Quality of the gate; stability of releases |
| **Mean time to restore (MTTR)** | Strength of rollback and recovery |

The last three plus lead time are the DORA four key metrics; cycle time is the
internal lens that explains them.

## Guiding principles

- **Prefer automation over documentation.** An automated script is executable
  documentation that must work and stays current; a document proving you did
  something does not guarantee you did it.
- **Compliance *through* the pipeline, not against it.** The pipeline is the best
  audit trail — lock down privileged environments, require approvals, and build
  authorization and auditing into the deploy path. Build binaries once and hash
  them to prove production matches source.
- **Release as often as possible** — at least every iteration, even with no users
  yet. "If it hurts, do it more frequently." Iterative, incremental delivery is
  the core of risk management, not a trade against it.
- **Don't work in silos.** Favor cross-functional teams; treat change management
  as risk management, with a back-out plan and an acceptance test per change.

## How this connects to the rest of the toolkit

- **`deployment-pipeline.md`** / **`release-strategies.md`** /
  **`database-change-management.md`** — the practices that move the environments,
  deployment and data areas up the model.
- **`cd-test-architecture.md`** and **`test-automation-maturity.md`** — the
  testing area's gate, and its own maturity ladder in more detail.
- **`architecture-assessment.md`** — the structural health of the thing being
  delivered, which caps how far the delivery side can go.
