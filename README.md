# omp-dev-team — an Oh-My-Pi marketplace

Four **independent** [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi) plugins.
Install any subset — they share nothing. A global installer sets up OMP and walks
you through them.

| Plugin | What it does |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Agentic dev team** — orchestrator + 32 specialist/critic agents, the `/specs` → `/plan` → `/build` → `/pr` workflow, **strict TDD** and human gates, ~78 skills, and blocking guard extensions. Port of [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (Bryan Finster). All-cloud tiers; keep the high-volume small tier cheap. |
| **[`copilot-preset`](plugins/copilot-preset/)** | **GitHub Copilot model preset** — route OMP (and the dev-team tiers) through `github-copilot` to run on a Copilot license. Config-only: tier→model mapping, post-June-2026 AI-credit pricing comparison, and MAI-Code-1-Flash wired in. |
| **[`token-diet`](plugins/token-diet/)** | **Aggressive token reduction** — RTK (compressed shell output), CodeGraph (MCP symbol/call-graph queries instead of grep+read), and a caveman terse-output skill — layered on OMP's native compaction/`astGrep`. |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps as a filesystem** — read repos/files/PRs/diffs via `ado://` URIs, create/checkout/push PRs, comment/vote, watch pipelines. PAT-authenticated, SQLite read cache. |

## Quick start (recommended)

The global installer installs OMP, registers this marketplace, and interactively
offers each plugin + its config, fixing your PATH at the end.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team
bash install.sh                 # Linux/macOS   (-y for non-interactive, --dry-run to preview)
#   pwsh -File install.ps1      # Windows
```

## Manual install

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team   # or:  add ./
omp plugin install dev-team@omp-dev-team
omp plugin install copilot-preset@omp-dev-team
omp plugin install token-diet@omp-dev-team
omp plugin install azure-devops-fs@omp-dev-team
```

Each plugin ships its own `install.sh` + `install.ps1` (installs that plugin's
tools at their latest versions) — see its README:

- **dev-team** → `bash plugins/dev-team/install.sh --apply-config` (prereq check + config). All-cloud; no local backend.
- **copilot-preset** → `bash plugins/copilot-preset/install.sh --apply-config`, then `omp` → `/login` → GitHub Copilot.
- **token-diet** → `bash plugins/token-diet/install.sh` (installs RTK + CodeGraph, indexes the repo), then enable the `codegraph` MCP server.
- **azure-devops-fs** → `bash plugins/azure-devops-fs/install.sh` (ensures Node), then set `AZURE_DEVOPS_ORG`/`AZURE_DEVOPS_PAT` and enable the `azure-devops` MCP server.

## Layout

```
install.sh · install.ps1               # global installer (OMP + marketplace + per-plugin prompts)
.claude-plugin/marketplace.json        # catalog (pluginRoot ./plugins)
plugins/
  dev-team/         agents/ skills/ commands/ rules/ extensions/ .mcp.json
                    config.snippet.yml · install.sh · install.ps1
                    skills/dev-team-knowledge/  (registries, rubrics, model-routing.json)
  copilot-preset/   config.snippet.yml · pricing.md · skills/ · install.{sh,ps1}
  token-diet/       .mcp.json · rules/ · skills/ · install.{sh,ps1}
  azure-devops-fs/  extensions/ commands/ skills/ rules/ knowledge/ .mcp.json · install.{sh,ps1}
```

Each plugin's extensions load from its own `package.json` `omp.extensions`; the
guard/routing extensions resolve their data relative to the plugin (so they work
whatever the consuming project's cwd is). Runtime state is written under the
consuming project's `.omp/state/`.

## Tested

Verified end-to-end on Linux: all `install.sh` pass `bash -n` + dry-run; all
`install.ps1` parse under PowerShell 7; all manifests are valid JSON; the 8
dev-team extensions compile under `bun`; RTK, CodeGraph, and OMP install via the
exact commands the scripts use; and all four plugins install through real OMP
(`omp plugin marketplace add ./` → `omp plugin install <name>@omp-dev-team`).

## Credits

- `dev-team` ports [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `token-diet` bundles [rtk-ai/rtk](https://github.com/rtk-ai/rtk), [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph), and [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman).
- `azure-devops-fs` mirrors the "GitHub as a filesystem" idea from [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
