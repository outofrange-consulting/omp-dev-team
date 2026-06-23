# Dev-team — startup-context trim

Goal: shrink the **always-loaded** context (injected into every request *and*
every subagent) without losing capability, by redirecting rules to where they're
actually used.

## OMP semantics verified (why this works)

From oh-my-pi source (`capability/rule-buckets.ts`, `system-prompt.ts`,
`task/executor.ts`):

- `alwaysApply: true` rules have their **full body** injected into the system
  prompt every session.
- Subagents spawned via `task` keep the parent's default prompt
  (`defaultPrompt.slice(0, -1)`, which **includes the alwaysApply rules**) and
  splice the agent persona in. `buildSystemPrompt` does **not** branch by agent
  type. → **Subagents inherit alwaysApply rules**, so trimming them saves tokens
  in every context, including the high-volume Haiku `smol` reviewers.

## What changed

| Always-loaded content (before) | After |
|---|---|
| `dev-team-operating-manual.md` — full pipeline, harness map, guard taxonomy, routing table, output guardrails (~7.0 KB) | Lean core: intro + North Star + on-demand pointers (~1.4 KB) |
| "Output guardrails" paragraph | **Removed** — duplicated `output-discipline.md` (itself always-loaded) |
| "How this maps to OMP" + guard taxonomy | **→ `skill://dev-team-harness`** (load on demand) — the guards are enforced by extensions regardless of whether the prose is loaded |
| "Request processing flow / ATDD / Decision log" | **Removed** — duplicated the orchestrator agent's own `## Three-Phase Workflow` / `## Decision Log` (loaded only when the orchestrator runs) |
| Model-routing table | Trimmed to a 3-line pointer to `model-routing.json` + `/routing` |
| `## Output discipline` block repeated in 9 team agents | **Removed** — redundant with the inherited `output-discipline` rule |

## Result

Always-loaded dev-team rules: **7609 B → 2762 B (−64%, ≈ −1.2K tokens)** on
**every** request and subagent — compounding on top of the existing
`discoveryMode`/disabled-tool startup trims. Plus ~7 lines saved per run in each
of the 9 team agents.

Guiding principle (the redirect rule): if an **extension/hook already enforces**
it → the prose is docs → on-demand skill, not `alwaysApply`. If it's
**agent-specific** → the agent prompt, not a global rule. If it's **duplicated**
→ one source.

## Verified
`ci-validate-json` 23/23 · dev-team extensions compile · unit suite green · no
eval/registry requires the removed sections · no dangling refs to the manual.
