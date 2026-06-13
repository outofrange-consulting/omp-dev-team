# dev-team

Persona-driven AI development team for [Oh-My-Pi](https://github.com/can1357/oh-my-pi),
ported from [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team).
32 agents, 3-phase orchestration, blocking guard extensions, and **local
small-tier model routing** (Sonnet/Opus stay cloud).

## Install

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team
omp plugin install dev-team@omp-dev-team
```

Then paste `config.snippet.yml` into `~/.omp/agent/config.yml` (sets model
routing + `skills.enableSkillCommands` + the task graph).

## Local small-tier model (the headline)

Agents declare a tier in `model:`. Small/pattern agents use `pi/smol`, resolved
by `modelRoles.smol`; balanced/deep agents pin `claude-sonnet-4-6` /
`claude-opus-4-8`. Only the small tier is local.

```sh
scripts/setup-local-models.sh          # pull Qwen3-Coder-30B-A3B (+ --fast / --next / --devstral)
```

Ships **cloud-safe** (`smol: claude-haiku-4-5`, `local.enabled:false`) so a
fresh install never blocks on a missing GPU. Flip to local:

```yaml
# ~/.omp/agent/config.yml
modelRoles:
  smol: ollama/qwen3-coder:30b   # local GPU small tier
# …and set "local": { "enabled": true } in model-routing.json to re-arm the gate.
```

Source of truth: `skills/dev-team-knowledge/model-routing.json`. The
`model-routing` extension probes the local backend, **blocks** a small-tier
dispatch when it's down (set `local.enabled:false` to disarm), and logs
dispatches to `<project>/.omp/state/model-routing.log`. Diagnose with `/routing`
or `/skill:model-routing-check`.

## Pipeline

`/specs` → `/plan` → `/build` → `/pr`, plus `/code-review` (`/review`),
`/review-agent`, `/continue`, `/triage`, `/design-doc`, `/issues-from-plan`,
`/model-routing-check`. Every skill is also `/skill:<name>`.

## Guardrails (extensions)

`path-guard` (secrets), `destructive-guard` + `/careful`, `freeze-guard`
(`/freeze` `/unfreeze`), `tdd-guard` (advisory), `review-gate` (blocks
`git commit` until `/review-approve`), `telemetry` + `/cost-report`,
`model-routing` (+ `/routing`). They intercept `tool_call` and block with a
reason — OMP's native blocking mechanism.

## Layout

```
.claude-plugin/plugin.json · package.json (omp.extensions)
agents/  skills/  commands/  rules/  extensions/  .mcp.json
skills/dev-team-knowledge/   # registries, rubrics, model-routing.json
config.snippet.yml  models.yml.example  scripts/
```
