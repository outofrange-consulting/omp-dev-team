# dev-team

> 🌐 **English** · [Français](README.fr.md)

An **agentic development team** for [Oh-My-Pi](https://github.com/can1357/oh-my-pi),
ported from Bryan Finster's [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team).
An orchestrator routes work through a **spec → plan → build → PR** workflow with a
**forced plan gate** (pre-analysis → plan → build → review), **tests required**,
and **human gates**, backed by 32 specialist and critic agents and blocking guard
extensions.

> Philosophy (Finster): AI is a high-pass filter for engineering discipline. The
> win comes from continuous delivery and defining what you build before you build
> it — not from picking a model. This plugin encodes that discipline as a forced
> plan gate plus tests as the safety net. (Test-first/TDD ordering is **not**
> enforced — it adds little for AI agents; the leverage is the plan gate.)

## Install

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team
omp plugin install dev-team@omp-dev-team
```

Then paste `config.snippet.yml` into `~/.omp/agent/config.yml` (model routing +
`skills.enableSkillCommands` + the task graph). The plugin's prerequisite checker:

```sh
bash plugins/dev-team/install.sh        # checks OMP/git/optional tools, installs .NET 10+ for serena-forge, can apply config
```

## The workflow

`/specs` → `/plan` → `/build` → `/pr`:

1. **`/specs`** — capture a feature as Intent + BDD scenarios + Architecture +
   Acceptance Criteria. Human approves.
2. **`/plan`** — turn the approved spec into a step-plan (each slice names its
   tests), with per-slice `Depends-on` metadata grouping slices into build
   **waves**. Five **plan-review critics** (acceptance-test, design, UX,
   strategic, parallelization) challenge it in parallel *before* you see it.
   Approve with **`/plan-approve`** to unlock the build (`plan-gate`); for a
   genuinely trivial task, `/scope --trivial` instead.
3. **`/build`** — execute the approved plan, building independent slices
   concurrently wave by wave. Tests are required per unit (test-first optional),
   verified green by **`/impl-verify`**.
4. **`/pr`** — run the quality gates and open the pull request.

For complex work the **orchestrator** runs **Research → Plan → Implement** with a
human gate between phases. Plus `/code-review` (`/review`), `/review-agent`,
`/continue`, `/triage`, `/design-doc` and `/issues-from-plan`. Every skill is also
available as `/skill:<name>`.

## Model tiers (all cloud, workload-shaped, provider-open)

Agents declare a **role list** in `model:` frontmatter. OMP takes the **first
resolvable** pattern, so every agent ends its list in `@default` and still routes
even if you never pasted the config snippet. The cheap end is split by **workload
shape** so neither half over-pays for the other's model:

| Tier | Frontmatter | For |
|---|---|---|
| nano | `"@smol, @default"` | pure lexical/checklist review + input-bound scan — no code semantics, no tool-use; highest volume |
| code | `"@smol, @default"` | cheap work needing code semantics or agentic tool-use: post-plan implementation (software-engineer, qa-engineer), structural code review (js-fp, svelte), codebase-recon |
| balanced | `"@plan, @default"` | most review agents + orchestrator + non-build team agents |
| design | `"@designer, @plan, @default"` | UI/UX and accessibility work — `designer` is a first-class OMP role we previously left dead |
| deep | `"@slow, @plan, @default"` | architecture/domain design synthesis and high-stakes security verdicts |

Two OMP facts drive this and are worth knowing:

- **`@task` is *not* a cheap tier.** It is deliberately session-inheriting
  (`model-resolver.ts:936-943`), so agents that declared it were running on the
  session model, not on a cheap one. They now declare `@smol`.
- **Only `smol`, `slow` and `designer` inherit from `default`**
  (`model-resolver.ts:946`). An unset `modelRoles.plan` therefore falls through to
  the session model **silently** — which is why the shipped snippet sets `plan`
  and `task` explicitly rather than relying on inheritance.

No agent pins a vendor model id. On base Anthropic the roles resolve to
Haiku/Sonnet/Opus; the **copilot-preset** plugin overlays Copilot-served models,
and any OpenAI-compatible provider works via **openai-compatible**. There is no
plugin-side resolver: the harness resolves `modelRoles` itself (see
`docs/upstream-v8-v10.md` for why the effort-band resolver was retired).

## Guardrails (extensions)

`plan-gate` (**blocks edits to production source until the task is scoped and a
plan is approved** — enforces pre-analysis → plan → build → review; `/scope`,
`/trivial`, `/plan-approve`, `/plan-reset`), `path-guard` (secrets),
`destructive-guard` + `/careful`, `freeze-guard` (`/freeze` `/unfreeze`),
`spec-guard` (**blocks edits to existing `.feature` specs** — fix code, not the
spec; `/allow-feature-edits` to override), `review-gate` (blocks `git commit`
until `/code-review` + `/review-approve`), `impl-verify` (`/impl-verify` strict
build + tests) and `telemetry` + `/cost-report`. They intercept `tool_call` and block with a reason — OMP's native
blocking mechanism.

## Layout

```
.claude-plugin/plugin.json · package.json (omp.extensions)
agents/  skills/  commands/  rules/  extensions/  .mcp.json
skills/dev-team-knowledge/   # registries (generated), rubrics, pricing
config.snippet.yml  install.sh  install.ps1
```
