# Deployment Pipeline

The path every change takes from version control to production, as automated
stages. Adapted from *Continuous Delivery* (Humble & Farley). Our
`cd-test-architecture.md` covers the *test* shape; this covers the *delivery*
shape. Reviewers and the platform-engineer use it to judge a pipeline design.

## Principles (non-negotiable)

- **Build binaries once.** The artifact built at the commit stage is the exact
  one promoted to every later stage and to production. Never rebuild per
  environment. Configuration is injected, not baked in.
- **Deploy the same way everywhere.** One deployment automation, used for dev,
  test, and prod — so the prod path is rehearsed thousands of times.
- **Deploy into a copy of production.** Test/CI environments mirror prod
  (OS, topology, config, representative data) so a stage that passes means
  something.
- **Each change propagates instantly.** The commit stage triggers on every
  check-in; each stage triggers the next on success. No nightly batching.
- **Production is locked down.** Only the pipeline changes prod — full audit
  trail, no manual drift.
- **Stop the line.** A red stage blocks promotion; fixing it is top priority.

## The stages (ordered)

| Stage | Purpose | Gate to pass |
|---|---|---|
| **Commit** | Compile, unit + fast integration tests, static analysis, build the artifact | Green in **minutes**; fast feedback or developers route around it |
| **Acceptance** | Automated functional/behavioral tests against deployed artifact | Behavior matches the spec's acceptance criteria |
| **Capacity / nonfunctional** | Performance, load, security, resilience as needed | Meets nonfunctional requirements |
| **Manual / UAT** | Exploratory + stakeholder validation (optional) | Human sign-off where required |
| **Release** | Promote the same artifact to production via the same automation | Releasable; rollback ready |

## Primary metric

**Cycle time** — commit to releasable — is the global metric. Use Theory of
Constraints: find the slowest/most painful stage, widen it, repeat. Track
deployment frequency, change-failure rate, and MTTR alongside it (DORA).

## Review checks (flag in a pipeline review)

- Artifact rebuilt per environment (not build-once) → drift risk.
- A stage that doesn't deploy to a production-like environment.
- Commit stage slower than ~10 min → developers will batch and bypass.
- Manual steps in the prod path that aren't a deliberate approval gate.
- No defined rollback for the release stage.

## Connections

- Test shape per stage → `cd-test-architecture.md`, `test-layer-gates.md`.
- Release/rollback mechanics → `release-strategies.md`.
- Where a team sits and how to improve → `cd-maturity-model.md`.
- Schema changes through the pipeline → `database-change-management.md`.
