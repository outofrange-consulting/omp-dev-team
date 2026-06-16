# omp-dev-team — an Oh-My-Pi marketplace

> 🌐 **English** · [Français](README.fr.md)

Four **independent** [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi) plugins.
Install any subset — they share nothing. A global installer sets up OMP and walks
you through them.

| Plugin | What it does |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Agentic dev team** — orchestrator + 32 specialist/critic agents, the `/specs` → `/plan` → `/build` → `/pr` workflow, **strict TDD** and human gates, ~78 skills, and blocking guard extensions. Port of [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (Bryan Finster). All-cloud tiers; keep the high-volume small tier cheap. |
| **[`copilot-preset`](plugins/copilot-preset/)** | **GitHub Copilot model preset** — route OMP (and the dev-team tiers) through `github-copilot` to run on a Copilot license. Config-only: tier→model mapping, post-June-2026 AI-credit pricing comparison, and MAI-Code-1-Flash wired in. |
| **[`token-diet`](plugins/token-diet/)** | **Aggressive token reduction** — ctx-wire (transparent command-output compression + secret scrub), CodeGraph (MCP symbol/call-graph queries instead of grep+read), a caveman terse-output skill, and a yagni minimal-code skill — layered on OMP's native compaction/`astGrep`. |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps as a filesystem** — read repos/files/PRs/diffs via `ado://` URIs (paginated), PR **gates/policies** + CI (builds/logs/run), create/checkout/push/complete PRs, comment/vote. PAT-authenticated, SQLite read cache. |
| **[`local-llm`](plugins/local-llm/)** | **Local models sized to your hardware** — detects VRAM/RAM, picks the best-fit GGUF models per role, installs Ollama (or llama.cpp), pulls them, and registers the `local-llm` provider. Hybrid: planning on cloud, execution/cheap roles local. |

## Quick start (recommended)

The global installer installs OMP, registers this marketplace, and interactively
offers each plugin + its config, fixing your PATH at the end.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team
bash install.sh                 # Linux/macOS   (-y for non-interactive, --dry-run to preview)
#   pwsh -File install.ps1      # Windows
```

**Works out of the box / defaults:** the global installer **reinstalls the selected
plugins to the latest** and **resets the managed model-roles + skills block** in
`~/.omp/agent/config.yml` (your old config is backed up to `config.yml.<timestamp>.bak`
first). With **copilot-preset** that wires, via GitHub Copilot: `smol`/`task` →
**Haiku**, `default`/`plan` → **Sonnet 4.6** (runs the dev-team orchestrator —
non-trivial work goes research → plan → implement → review), `slow` → **Opus**;
without it, the same tiers on Anthropic ids. token-diet's ctx-wire + CodeGraph and
the skills are enabled too. Tools already present are kept — pass **`--update`**
(`-Update`) to also refresh bun/node/omp; **`--no-config`** to leave your config untouched.

**Corporate proxies (Zscaler / Trend Micro under WSL):** if a TLS-intercepting
proxy breaks certificate checks, the UNIX installers give you two options:

- **Preferred — trust the corporate CA:** `--ca-file=/path/to/corp-root-ca.pem`
  (or `OMP_CA_FILE=…`). Verification stays **on**; node/bun, git, curl/wget, Python
  and **Go tools (Ollama model pulls)** are pointed at your CA via
  `NODE_EXTRA_CA_CERTS`/`SSL_CERT_FILE`/`CURL_CA_BUNDLE`/`GIT_SSL_CAINFO`, and it's
  **persisted to your shell profile** so `omp` and `ollama pull` trust it later too.
  On **WSL you don't even need the .pem** — `--ca-from-windows` exports the Windows
  trust store (incl. the corporate roots) automatically, and the global installer
  **offers it when it detects WSL**.
- **Escape hatch — bypass:** `--insecure-tls` (or `OMP_INSECURE_TLS=1`) disables
  verification for that run (curl/wget incl. piped installers, git, node/bun/npm).
  It can't bypass Go/libcurl tools (Ollama, etc.) — use `--ca-file` for those.

The global installer propagates either choice to the plugin installers. Run the
installers **without `sudo`** (everything is per-user: `~/.bun`, `~/.local/bin`, `~/.omp`).

## Manual install

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team   # or:  add ./
omp plugin install dev-team@omp-dev-team
omp plugin install copilot-preset@omp-dev-team
omp plugin install token-diet@omp-dev-team
omp plugin install azure-devops-fs@omp-dev-team
omp plugin install local-llm@omp-dev-team
```

> **Important — extension modules.** OMP does **not** load extension modules
> (a plugin's `package.json` `omp.extensions`) from a marketplace cache install —
> only skills/commands/agents/rules/MCP surface that way. The plugins whose core
> behavior *is* an extension — **azure-devops-fs** (the `ado` tool),
> **dev-team** (the blocking guards + model-routing), and **local-llm** (the
> provider) — therefore need their installer to run too. The global `install.sh`
> and each plugin's `install.sh`/`install.ps1` mirror those modules into OMP's
> native `~/.omp/agent/extensions/<plugin>/` dir (always discovered, survives
> config resets), so the `ado` tool / guards / provider actually load. A bare
> `omp plugin install <name>@omp-dev-team` alone will show the skill but **not**
> register the tool.

Each plugin ships its own `install.sh` + `install.ps1` (installs that plugin's
tools at their latest versions) — see its README:

- **dev-team** → `bash plugins/dev-team/install.sh --apply-config` (prereq check + config). All-cloud; no local backend.
- **copilot-preset** → `bash plugins/copilot-preset/install.sh --apply-config`, then `omp` → `/login` → GitHub Copilot.
- **token-diet** → `bash plugins/token-diet/install.sh` (installs ctx-wire + CodeGraph, indexes your repos), then enable the `codegraph` MCP server.
- **azure-devops-fs** → `bash plugins/azure-devops-fs/install.sh` (ensures Node, prompts for org/project/PAT), then enable the `azure-devops` MCP server.
- **local-llm** → `bash plugins/local-llm/install.sh` (detects VRAM/RAM, asks, installs Ollama/llama.cpp, pulls the best-fit models, wires roles).

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
  local-llm/        extensions/ (catalog/selector/detect/emit) · skills/ · install.{sh,ps1}
```

Each plugin's extensions load from its own `package.json` `omp.extensions`; the
guard/routing extensions resolve their data relative to the plugin (so they work
whatever the consuming project's cwd is). Runtime state is written under the
consuming project's `.omp/state/`.

## Agent Package Manager (APM) & duplicate definitions

If you use [Agent Package Manager](https://github.com/) and run `apm compile --all`,
the same agents/skills/rules get written into `.claude`, `.copilot`, `.cursor`,
`.agents`, … next to `.omp`. **OMP does not load them multiple times** — it
de-duplicates by name (first match wins) *before* loading, so duplicates cost **no
extra tokens** and are not double-registered:

- **agents / commands / skills** are scanned only from `.omp` › `.claude` › `.codex`
  › `.gemini` (project before user); identical skill files are additionally
  realpath-deduped. `.copilot` and `.cursor` are **not** scanned for these.
- **rules** are name-deduped across providers `native › agents › cursor › windsurf
  › cline`; shadowed same-name rules are excluded from the active set.

Notes:

- **Don't delete the other directories.** `apm compile --all` creates `.claude` /
  `.copilot` / `.cursor` on purpose for Claude Code / Copilot / Cursor, which need
  them. Removing them to "de-dupe" would break those tools — and OMP already
  ignores the extras.
- OMP silently uses the **highest-precedence** copy and shadows the rest. To be
  sure OMP uses a specific variant, keep the canonical one in `.omp/` (or
  `.claude/`). For skills you can also pin/exclude with `skills.includeSkills` /
  `skills.ignoredSkills` in your config.

## Tested

Verified end-to-end on Linux: all `install.sh` pass `bash -n` + dry-run; all
`install.ps1` parse under PowerShell 7; all manifests are valid JSON; the 8
dev-team extensions compile under `bun`; ctx-wire, CodeGraph, and OMP install via
the exact commands the scripts use; and all five plugins install through real OMP
(`omp plugin marketplace add ./` → `omp plugin install <name>@omp-dev-team`).

## Credits

- `dev-team` ports [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `token-diet` bundles [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire), [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph), [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman), and [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (yagni).
- `azure-devops-fs` mirrors the "GitHub as a filesystem" idea from [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
