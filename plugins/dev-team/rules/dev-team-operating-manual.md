---
description: Dev-team operating manual — North Star + pointers (always loaded; kept deliberately small)
alwaysApply: true
---

# Dev-Team (Oh-My-Pi port)

A persona-driven AI dev team on OMP (ported from `bdfinst/agentic-dev-team`). The
**orchestrator** agent is the dispatcher; it routes work to specialists via the
`task` tool. This rule is injected into **every** context (main and every
subagent), so it stays small on purpose — detail lives where it's used, loaded
on demand.

## North Star

Every change must reduce friction for someone getting work done: **fewer
missteps, less rework, lower token cost.** Measure friction, don't assume it —
the `telemetry` extension and `/cost-report` close the loop. A change that
cannot name the friction it removes does not ship.

## Where the detail lives (load on demand — do not inline it here)

- **Orchestration pipeline** — Research → Plan → Implement, human gates, the
  five plan-review personas, the three-stage inline review, acceptance scenarios, and the
  decision log: owned by the **orchestrator** agent prompt (`## Three-Phase
  Workflow` / `## Decision Log`). Don't restate it in always-loaded context.
- **Model resolution** — **native, no plugin resolver.** Each agent's `model:`
  frontmatter declares a role floor (`@smol` / `@plan` / `@slow` / `@designer`,
  with `@default` last as a fallback); OMP resolves it through `modelRoles`.
  Depth per agent is `thinking-level:`. Per *call*, the `task` tool's
  `effort: lo|med|hi` carries the task size — passed during spec/plan only,
  never during build/review. Full rule: orchestrator agent, **§ Resolution
  Procedure**. No concrete model id belongs in a prompt.
- **Output discipline** — the `output-discipline` rule (always loaded): artifacts
  to files, no narration, plan-only means plan-only, name your evidence.
- **Verification / quality gates** — the `no-disable-analyzers` and
  `source-of-truth` rules, plus `/impl-verify` (strict stack build + tests with
  a bounded fix counter).

## Session canary (context-loaded check)

This file is the always-loaded operating manual. The `canary` extension verifies
at session start that the *installed* copy of this rule is intact — present,
still `alwaysApply: true`, still carrying the sentinel below. A `CANARY FAIL`
notice means the dev-team context did not load (botched install, broken
frontmatter, stale mirror): fix it before working, not twenty minutes in. Run
`/canary` to re-check on demand. Keep the sentinel byte-identical here, in
`extensions/canary.ts`, and in `scripts/ci-framework-compliance.mjs` (check E).

<!-- dev-team-canary: DT-CANARY-7Q2F -->
