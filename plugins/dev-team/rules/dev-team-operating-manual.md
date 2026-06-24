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
  five plan-review personas, the three-stage inline review, ATDD, and the
  decision log: owned by the **orchestrator** agent prompt (`## Three-Phase
  Workflow` / `## Decision Log`). Don't restate it in always-loaded context.
- **Model routing** (tier → model) — source of truth is
  `skill://dev-team-knowledge/model-routing.json`, enforced by the
  `model-routing` extension; inspect with `/routing`.
  Tiers: `pi/smol` (cheap, high-volume lexical/checklist review),
  `claude-sonnet-4-6` (balanced; most agents + the orchestrator),
  `claude-opus-4-8` (deep reasoning). Keep `smol` on the cheapest capable model.
- **Output discipline** — the `output-discipline` rule (always loaded): artifacts
  to files, no narration, plan-only means plan-only, name your evidence.
- **Verification / quality gates** — the `no-disable-analyzers` and
  `source-of-truth` rules, plus `/impl-verify` (strict stack build + tests with
  a bounded fix counter).
