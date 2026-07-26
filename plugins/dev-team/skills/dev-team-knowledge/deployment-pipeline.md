# Deployment Pipeline Anatomy

The path every change takes from version control to production, as automated
stages, plus the configuration and environment discipline it depends on. Source:
*Continuous Delivery* (Humble & Farley) Ch. 5 (anatomy), Ch. 2 (configuration
management), Ch. 11 (infrastructure and environments). Read by reviewers and the
`platform-engineer` agent when judging a pipeline design.

Advisory boundary: `cd-test-architecture.md` covers the *test* shape of the
commit gate; this file covers the *delivery* shape around it.

A deployment pipeline is the automated manifestation of the process for getting
software from version control to the user. Each change enters once and is either
proven releasable or rejected.

## The stages

A change flows through ordered stages; success in one triggers the next.

| Stage | Purpose | Gate |
|-------|---------|------|
| **Commit** | Compile, unit + component + contract tests, static analysis, build the artifact. Fast — minutes. | Blocks merge — see `cd-test-architecture.md` |
| **Acceptance** | Automated acceptance tests against a production-like deploy of the built artifact | Behavior matches the executable spec |
| **Capacity / nonfunctional** | Performance, load, security and resilience tests as a stage, not an afterthought | Meets the agreed budgets |
| **Manual / UAT** | Exploratory testing, demos, showcases — on demand | Human judgment |
| **Release** | Push-button deploy of the *same* artifact to production | Approved; smoke test green; rollback ready |

## The pipeline principles

- **Build your binaries only once.** Compile and package in the commit stage,
  store the artifact in a repository (not in version control), and **promote the
  same binary** through every stage. Never rebuild from source per environment —
  a rebuilt binary is a different binary.
- **Binaries are environment-agnostic.** Separate code (constant across
  environments) from configuration (varies per environment). A binary that only
  runs in one environment is a defect.
- **Deploy the same way to every environment.** Dev, test and production use the
  identical automated deploy process, so the production path is rehearsed
  hundreds of times before it matters.
- **Smoke-test every deployment.** An automated post-deploy check confirms the app
  and its dependencies (DB, message bus, external services) are up. After unit
  tests, this is the most valuable test you have.
- **Deploy into a copy of production.** Test/CI environments match production in
  infrastructure, OS config and patches, app stack, and relevant data state — so
  a stage that passes means something.
- **Each change propagates instantly.** The first stage triggers on every
  check-in; each stage triggers the next on success — no nightly batching. When
  busy, build off the most recent set of changes rather than queuing every one.
- **Stop the line.** A red stage blocks promotion and fixing it is the top
  priority; a pipeline people route around is not a pipeline.
- **Cycle time is the primary global metric** (commit → releasable). Apply the
  Theory of Constraints: find the bottleneck stage and elevate it. Coverage,
  defect counts and build duration are secondary diagnostics. Radiate them.
- **The pipeline is part of the product.** Build it incrementally; version, test
  and refactor it with the same care as the application.

## Configuration management (Ch. 2)

| Practice | What it means |
|----------|---------------|
| **One version-controlled source per environment** | Deploy-time config lives in a single source (properties files / directory service / database), selected per environment by hostname or env var. One source for all apps in all environments. |
| **No config in the binary** | The same artifact reads its config from the environment; no per-environment builds. |
| **Secrets are not in version control** | Inject secrets at deploy/runtime (a secret store, vault, or sealed env); never bake credentials into the image or commit them. Image-level checks live in the `docker-image-audit` skill. |
| **Config is testable** | A wrong or missing config value should fail fast at startup — caught by the smoke test — not silently degrade. |

## Infrastructure and environments (Ch. 11)

- **Specify desired state as version-controlled configuration** — OS install
  definitions, middleware, network, data-center automation. Provisioning is
  automated so any environment can be re-created from scratch to a known-good
  state in a predictable time.
- **All environments are production-like**, managed with the *identical*
  techniques used for production.
- **Know the actual state** through instrumentation and monitoring; infrastructure
  should self-correct toward the desired state.
- **Lock down production.** Only the pipeline changes it, which gives a complete
  audit trail of who changed what and when. No manual changes on production.

## Review checks (flag these in a pipeline review)

- Artifact rebuilt per environment instead of promoted → drift risk, and the
  thing you tested is not the thing you shipped.
- A stage that does not deploy to a production-like environment → its green is
  not evidence.
- Commit stage slower than ~10 minutes → developers will batch and bypass it.
- Manual steps in the production path that are not a deliberate approval gate.
- No defined, rehearsed rollback for the release stage.
- Secrets or per-environment values baked into the artifact.

## Scope note (advisory boundary)

This plugin **designs and assesses** pipelines and **plans** changes to fit them.
It does not author IaC stacks (Terraform/Helm), operate artifact repositories, or
execute deployments. Recommend those; don't simulate them.

## How this connects to the rest of the toolkit

- **`cd-test-architecture.md`** and **`test-layer-gates.md`** — the commit-stage
  gate's test types and determinism rules; this file places that gate inside the
  whole pipeline.
- **`release-strategies.md`** — what the release stage actually does (blue-green,
  canary, rollback, decoupling deploy from release).
- **`database-change-management.md`** — how schema changes travel through these
  stages without blocking rollback.
- **`cd-maturity-model.md`** — cycle time, traceability (build-once + hash) and
  production lock-down are scored there as you move up the model.
