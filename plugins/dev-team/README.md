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
bash plugins/dev-team/install.sh        # checks OMP/git/optional tools, can apply config
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
`/continue`, `/triage`, `/design-doc`, `/issues-from-plan`, and the `/routing`
diagnostic. Every skill is also available as `/skill:<name>`.

## Model tiers (all cloud)

Agents declare a tier in `model:` frontmatter, resolved natively by your
`modelRoles`:

| Tier | Frontmatter | For |
|---|---|---|
| small | `pi/smol` (cheap cloud, default Haiku) | lexical/structural checks, checklist reviews — high volume |
| balanced | `claude-sonnet-4-6` | most team & review agents, orchestrator |
| deep | `claude-opus-4-8` | cross-file reasoning, design synthesis, threat modeling, recon |

The high-volume **small tier** is where token spend concentrates — keep it cheap.
Point `modelRoles.smol` at `claude-haiku-4-5`, or (with the **copilot-preset**
plugin) at `github-copilot/gpt-5-mini` to run it on your Copilot license. Pair
with **token-diet** to cut tokens further. Source of truth:
`skills/dev-team-knowledge/model-routing.json`; diagnose with `/routing`.

## Guardrails (extensions)

`plan-gate` (**blocks edits to production source until the task is scoped and a
plan is approved** — enforces pre-analysis → plan → build → review; `/scope`,
`/trivial`, `/plan-approve`, `/plan-reset`), `path-guard` (secrets),
`destructive-guard` + `/careful`, `freeze-guard` (`/freeze` `/unfreeze`),
`spec-guard` (**blocks edits to existing `.feature` specs** — fix code, not the
spec; `/allow-feature-edits` to override), `review-gate` (blocks `git commit`
until `/code-review` + `/review-approve`), `impl-verify` (`/impl-verify` strict
build + tests), `telemetry` + `/cost-report`, `model-routing` (dispatch tier log
+ `/routing`). They intercept `tool_call` and block with a reason — OMP's native
blocking mechanism.

## Layout

```
.claude-plugin/plugin.json · package.json (omp.extensions)
agents/  skills/  commands/  rules/  extensions/  .mcp.json
skills/dev-team-knowledge/   # registries, rubrics, model-routing.json
config.snippet.yml  install.sh  install.ps1
```
