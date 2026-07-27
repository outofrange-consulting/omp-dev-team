# Extraction from upstream agentic-dev-team (v7.x)

> **SUPERSEDED.** This records the hand-maintained port. `dev-team` is now a
> mechanical re-port of upstream v10.20.0 produced by
> `scripts/port-upstream-dev-team.mjs`; see `docs/upstream-v8-v10.md` and
> `docs/port-contract.md`. Kept for the decision history only.

Survey of `bdfinst/agentic-dev-team` recent releases (we ported an earlier
version and have since evolved heavily), and what we pulled into our OMP port.

## Upstream recent evolution

| Release | Highlight |
|---|---|
| v7.0.0 | effort-band model routing (replaces `model:` tiers) — breaking |
| v7.2.0 | tier plan review, batch inline review, headless approval gates |
| v7.3.0 | **objective task classifier + no-plan fast path**; trust review signals over coverage saturation |
| v7.4.0 | **adversarial self-challenge across all review agents** |
| v7.5.0 | test-tooling knowledge (xUnit Test Patterns, Working Effectively with Legacy Code) |
| v7.6.0 | DDD (Evans) + Continuous Delivery (Humble & Farley) knowledge |
| — | new **security-assessment** plugin: deterministic-first SAST (semgrep/gitleaks/trivy) + LLM judgment |

## Extracted in this PR

1. **Objective task-size classifier + fast path** (v7.3.0) →
   `skills/dev-team-knowledge/task-size-classifier.md`, wired into the
   orchestrator pre-analysis. Objective signals only (`files_changed`,
   `loc_delta`, `slice_count`, `wave_count`, `has_complex_step`,
   `decision_axis_triggered`) classify `trivial`/`standard`/`complex`; `trivial`
   takes the **no-plan fast path** via our `/scope --trivial`. This makes the
   plan-gate's trivial decision principled instead of vibes and saves tokens
   (upstream: ~65% fewer turns / ~45% lower cost on small tasks). Quality gates
   are kept — review + `/impl-verify` still run.
2. **Adversarial self-challenge across all review agents** (v7.4.0). We already
   had the protocol and per-agent confidence, but only 7/18 review agents wired
   it. Added the `## Self-Challenge` section to the remaining **11** agents and
   authored their per-agent challenge blocks in
   `adversarial-review-protocol.md` (a11y, naming, performance, concurrency,
   js-fp, refactor-opportunity, spec-compliance, doc, svelte, token-efficiency,
   claude-setup). Now **18/18** review agents run the challenger loop and emit a
   confidence level.

## Already present in our port (no action)

`/careful`, `/freeze`, `review-gate` (pre-commit gate), worktree isolation,
`telemetry`/`/cost-report`, and — beyond upstream — our own `plan-gate`,
`/impl-verify`, and `token-diet` stack.

## Deliberately NOT ported (with rationale)

- **Effort-band model routing (v7.0.0).** Breaking change that replaces tiers.
  We intentionally kept the tier model at the time because it was wired to
  `copilot-preset` and `model-routing.json` + the pre-dispatch routing
  extension. **Superseded:** that resolver is retired (see
  `docs/upstream-v8-v10.md`); tiers are now OMP roles (`@smol`/`@task`/`@plan`/
  `@slow`) resolved by the harness. Re-architecting would have churned the Copilot
  cost story for little gain. Revisit only if we adopt per-call effort signals.
- **security-assessment plugin (deterministic-first SAST).** Genuinely new and
  on-brand (run semgrep/gitleaks/trivy first, spend LLM tokens only to triage —
  a strong token-efficient pattern). But it's a **separate plugin** with external
  tool dependencies and overlaps our `semgrep-analyze` skill + `security-review`/
  `security-engineer` agents. Recommended as a **dedicated follow-up plugin**,
  not squeezed into this PR.
- **DDD / CD / test-tooling knowledge (v7.5/7.6).** Largely covered by our
  `domain-driven-design`, `cd-test-architecture`, and `mutation-testing` skills.
  Cherry-pick specific patterns later if a gap shows up.

## Verified
`ci-validate-json` 23/23 · all 18 review-agent `#anchor` refs resolve in the
protocol · extensions compile · unit suite green.
