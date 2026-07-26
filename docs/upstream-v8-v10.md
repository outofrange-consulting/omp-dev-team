# Upstream extraction — agentic-dev-team v8 → v10.20.0

The `docs/upstream-v7*.md` files record what this port absorbed up to ADT v7.9.
Upstream is now at **v10.20.0** (HEAD `37aa6a5`, 2026-07-26). Everything from v8
onward was unabsorbed until this pass. This file is the current baseline, so
"track upstream closely" has something concrete to diff against.

**Surveyed by** cloning `bdfinst/agentic-dev-team` and reading the tree; every
claim below is from a file in that clone, not from release notes.

## The repo restructured

ADT is no longer a single plugin. It is a marketplace of three:

| upstream plugin | what it is | our position |
|---|---|---|
| `dev-team` | the agentic team we port | ported |
| `security-assessment` | 13 security agents, separate lifecycle | **not ported** — a separate marketplace decision, not an omission |
| `marketplace-dev` | plugin-authoring tooling (`agent-create`, `plugin-audit`, the agent-contract validator) | not applicable — it validates the Claude Code contract, not OMP's |

Counts at HEAD: **46 agents**, **92 skills**, **57 knowledge files**, and **no
`commands/` directory at all** — upstream exposes its workflow purely as skills.

## Decisions we absorbed in this pass

**ADR-0026 — native `model:`/`effort:` frontmatter, band resolver retired.**
The single most consequential one. Upstream deleted `hooks/agent_model_resolve.py`,
`hooks/lib/model_resolve.py`, `knowledge/model-routing.json`,
`knowledge/calibration-floors.json`, `skills/model-routing-check/`,
`scripts/agent_calibrate.py`, ~15 test files and two docs — six ADRs' worth of
hand-built machinery — on the finding that the harness already resolves
`model:`/`effort:` itself. Its rationale applies to us verbatim: *"Zero
plugin-owned code stands between an agent's frontmatter and the model/effort the
harness actually runs it with."*

We had built the same thing (`extensions/model-routing.ts` +
`skills/dev-team-knowledge/model-routing.json` + an effort-band ladder) and have
now retired it for the OMP-native equivalent: `modelRoles` + `@role` aliases +
per-agent `thinking-level:` + the `task` tool's per-call effort.

Three defects of our own version reinforced the call:
- it branched on the literal strings `"opus"` and `"sonnet"` — an Anthropic-name
  dependency inside a provider-open port;
- a hook reached into orchestrator state (`plan-gate.json`), which upstream's
  ADR-0019 forbids;
- ADR-0022 forbids shipping a dispatch mechanism as default behaviour without a
  measured win, and `docs/effort-band-routing.md` cited none.

**ADR-0017 — single build cadence.** Upstream removed classic TDD as an opt-in.
Note *why*: not a quality gap, a cost result — Code-First $0.99/cell at 0.961
quality (0.968 quality-per-dollar) vs Classic TDD $1.59 at 0.966 (0.608). We had
already landed on test-after; we adopted upstream's measured rationale in place
of our unevidenced one.

**ADR-0029 — `implementer` folded into `software-engineer`.** Its per-step
context moved into the build skill; the orchestrator dispatches
`software-engineer` directly.

**ADR-0016 — rely on harness-native compaction.** *"Rebuilding any of this in
the plugin would duplicate harness behavior we do not control and cannot keep in
sync."* Upstream's entire token surface is measurement and authoring hygiene; it
intercepts nothing at runtime. This is the sharpest available argument against
what token-diet used to do, and drove that plugin's refocus.

## Decisions we deliberately did NOT absorb

| upstream decision | why not |
|---|---|
| **ADR-0027** — mandatory mechanically-derived `color:` on every agent | **Inert in OMP.** A repo-wide grep of the OMP source for a `color` field in agent frontmatter returns nothing. OMP's colour concept is per-*role* tag metadata in user settings, not per-agent. |
| **ADR-0028** — mandatory `memory: project` on every code-modifying agent | **Unsatisfiable in OMP.** `docs/memory.md`: *"The pipeline is skipped for subagents."* The exact-equality gate cannot be emulated. |
| **ADR-0021** — Claude-only model routing, no cross-provider tier | Rejected on purpose. ADR-0021's own revisit trigger #1 is *"the harness can natively dispatch a sub-agent to a non-Claude model"* — which OMP satisfies today. Model-openness is the point of this port. |
| **`effort: high` uniformly on every agent** | ADR-0026:141-151 flags it as an uncalibrated deliberate reset ("a11y-review… now runs that cheap model at effort: high, a combination never calibrated"). Our per-agent `thinking-level:` is the better-calibrated artifact. |
| `upgrade`, `version` skills | OMP ships `/marketplace update`, `/plugins`, `/reload-plugins` natively. |
| `headless-run`, `long-eval` | Claude Code Remote container/session-id workarounds; no OMP analogue. |
| `harness-e2e-check` | Tests the Python hooks we replaced with TypeScript extensions — a rewrite, not a port. |
| `proxy-resilience` + `proxy-connectivity.md` | Anthropic-proxy-shaped by construction; OMP owns provider retry. |

## The frontmatter contract, translated

Upstream's contract — shipped by its `marketplace-dev` plugin as
`knowledge/agent-contract.json`, a verbatim capture of Anthropic's sub-agent
docs — does not map field-for-field onto OMP. OMP's parser is `packages/coding-agent/src/discovery/helpers.ts`
(`parseAgentFields`). The translation this port uses:

| upstream (Claude Code) | OMP equivalent | note |
|---|---|---|
| `model: sonnet\|opus\|haiku\|fable\|inherit` | `model:` — a CSV/list of patterns, **first resolvable wins** | so a fallback list is free insurance if the user never pasted the config snippet |
| `effort: low…max` | `thinking-level:` | OMP has **no** `effort:` key in frontmatter. A `:level` suffix on the model value silently outranks `thinking-level` — use one surface, not both. |
| `skills:` (preload) | `autoload-skills:` | same mechanic as `/skill:<name>` |
| `color:`, `memory:`, `permissionMode:`, `maxTurns:`, `isolation:` | — | ignored silently by OMP; `scripts/ci-framework-compliance.mjs` check M fails the build if one appears |
| — | `read-summarize: false` | no upstream equivalent; forces verbatim file content for reviewers that must see exact code |
| — | `spawns:`, `blocking:`, `output:`, `prewalk:` | OMP-only |

Role aliases: `@smol` is canonical; `pi/smol` is the **legacy** prefix
(`packages/coding-agent/src/config/model-roles.ts:9-12`). Both resolve; we write
the canonical form.

## Still open (tracked, not done)

Ported in a follow-up pass, in rough value order: `/ship` (upstream's headline
entry point, idempotent per issue), the `build` and `plan` skill reconciliations
(290 and 259 diff lines, the latter bidirectional — ours is the longer one),
`co-evolution-audit`, `test-audit-disable`, `agent-readiness`,
`competitive-analysis`, the react/vue/angular reactivity reviewers, and an
`omp-setup-review` rewritten from upstream's `claude-setup-review`.
