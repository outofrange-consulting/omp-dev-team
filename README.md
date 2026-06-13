# omp-dev-team — an Oh-My-Pi marketplace

Two **independent** [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi) plugins.
Install either, both, or neither — they share nothing.

| Plugin | What it does |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | Persona-driven AI development team: 32 agents, 3-phase orchestration (`/specs` → `/plan` → `/build` → `/pr`), 78 skills, blocking guard extensions, and **local small-tier model routing** (Sonnet/Opus stay cloud; the cheap review agents run on your GPU). Port of [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team). |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps as a filesystem**: read repos/files/PRs/diffs through `ado://` URIs, create/checkout/push PRs, comment/vote, watch pipelines. PAT-authenticated, SQLite read cache. The ADO analog of OMP's GitHub `pr://`/`issue://` + `github` tool. |
| **[`copilot-preset`](plugins/copilot-preset/)** | **GitHub Copilot model preset**: a ready config that routes OMP (and the dev-team's tiers) through `github-copilot`, so teams run on their Copilot license. Config-only — paste the snippet; includes the tier→Copilot model mapping, post-June-2026 AI-credit pricing comparison, and MAI-Code-1-Flash. |
| **[`token-diet`](plugins/token-diet/)** | **Aggressive token reduction**: RTK (compressed shell output), CodeGraph (MCP symbol/call-graph queries instead of grep+read), and a caveman terse-output skill — layered on OMP's native compaction/`astGrep`. Always-on routing rule + setup script. |

## Install

This repo is an OMP **marketplace** (catalog at `.claude-plugin/marketplace.json`,
plugins under `plugins/<name>/`).

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team   # or:  add ./
omp plugin install dev-team@omp-dev-team
omp plugin install azure-devops-fs@omp-dev-team
omp plugin install copilot-preset@omp-dev-team
omp plugin install token-diet@omp-dev-team
```

Then follow each plugin's README:
- **dev-team** → pull a local model (`plugins/dev-team/scripts/setup-local-models.sh`) and paste `plugins/dev-team/config.snippet.yml` into `~/.omp/agent/config.yml`.
- **azure-devops-fs** → set `AZURE_DEVOPS_PAT` + `AZURE_DEVOPS_ORG`.
- **copilot-preset** → authenticate Copilot (`/login`) and paste `plugins/copilot-preset/config.snippet.yml`.
- **token-diet** → run `plugins/token-diet/scripts/setup.sh` (installs RTK + CodeGraph), then enable the `codegraph` MCP server.

## Layout

```
.claude-plugin/marketplace.json        # catalog (pluginRoot ./plugins)
plugins/
  dev-team/         .claude-plugin/plugin.json · package.json (omp.extensions)
                    agents/ skills/ commands/ rules/ extensions/ .mcp.json
                    skills/dev-team-knowledge/  (registries, rubrics, model-routing.json)
  azure-devops-fs/  .claude-plugin/plugin.json · package.json (omp.extensions)
                    extensions/ commands/ skills/ rules/ knowledge/ .mcp.json
```

Each plugin's extensions load from its own `package.json` `omp.extensions`; the
guard/routing extensions resolve their data relative to the plugin (so they work
whatever the consuming project's cwd is). Runtime state is written under the
consuming project's `.omp/state/`.

## Credits

- `dev-team` ports [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `azure-devops-fs` mirrors the "GitHub as a filesystem" idea from [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
