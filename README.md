# omp-dev-team — an Oh-My-Pi marketplace

> 🌐 **English** · [Français](README.fr.md)

Six **independent** [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi) plugins.
Install any subset — they share nothing. A global installer sets up OMP and walks
you through them.

| Plugin | What it does |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Agentic dev team** — a *verbatim* port of [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) v10.20.0 (Bryan Finster): orchestrator + 45 specialist/critic agents, 93 skills including **`/ship`** (spec → plan → build → review → PR as one idempotent command), a 58-file knowledge corpus, and upstream's 38 Python hook invocations run **unmodified**. 456 of 567 upstream files land byte-identical; the rest carry only the Claude Code → OMP format conversion, applied by [`scripts/port-upstream-dev-team.mjs`](scripts/port-upstream-dev-team.mjs) so the next upstream bump is one command. Model-open: agents route through OMP roles (`@smol`/`@plan`/`@slow`), never a vendor id. **Requires `python3`.** |
| **[`copilot-preset`](plugins/copilot-preset/)** | **GitHub Copilot model preset** — route OMP (and the dev-team tiers) through `github-copilot` to run on a Copilot license. Config-only: tier→model mapping, post-June-2026 AI-credit pricing comparison, and MAI-Code-1-Flash wired in. |
| **[`token-diet`](plugins/token-diet/)** | **What OMP's own context tooling doesn't cover** — ctx-wire filters that collapse `dotnet publish/pack/run/tool` output *semantically* (OMP truncates mechanically: 50 KB tail, 768-byte column cap), including French locales, plus the `caveman` skill for terse agent **output**. Deliberately small: OMP 17 absorbed read/context dedup, cost + cache statusline segments, and secret redaction, so those were removed rather than duplicated. |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps as a filesystem** — read repos/files/PRs/diffs via `ado://` URIs (paginated), PR **gates/policies** + CI (builds/logs/run), create/checkout/push/complete PRs, comment/vote. Backed by the **Azure CLI** (`az` + the azure-devops extension), PAT auth, SQLite read cache; works behind corporate TLS proxies. |
| **[`openai-compatible`](plugins/openai-compatible/)** | **Any OpenAI-compatible provider** — point it at a LiteLLM, Ollama, vLLM, or LocalAI endpoint (name + URL + API key); the installer lists the models and writes the provider into `~/.omp/agent/models.yml` with runtime discovery, usable as `<name>/<model-id>`. API key stored chmod 600, never in env. |
| **[`datadog`](plugins/datadog/)** | **Datadog observability from the terminal** — via the Datadog [`pup`](https://github.com/DataDog/pup) CLI (logs, metrics, traces/APM, monitors, incidents, dashboards, SLOs, RUM, security/audit, CI test visibility, LLM observability). One broad `datadog` skill drives pup; installer sets up pup + auth. |

## Quick start (recommended)

The global installer installs OMP, registers this marketplace, and interactively
offers each plugin + its config, fixing your PATH at the end.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team
bash install.sh                 # Linux/macOS   (-y for non-interactive)
#   pwsh -File install.ps1      # Windows
```

**Works out of the box / defaults:** the global installer **reinstalls the selected
plugins to the latest** and brings runtimes/OMP/tooling **up to date by default**
(pass **`--no-update`** / `-NoUpdate` to keep tools already installed). It then
**merges** the managed model-roles + skills defaults into `~/.omp/agent/config.yml`
and the team MCP servers into `~/.omp/agent/mcp.json` — **anything you've already set
is preserved** (no clobber, no backup needed). With **copilot-preset** the tiers wire,
via GitHub Copilot: `smol`/`task` → **Haiku**, `default`/`plan` → **Sonnet 5** (runs
the dev-team orchestrator + architecture/domain design — non-trivial work goes
research → plan → implement → review), `slow` → **Opus** (high-stakes security
verdicts); without it, the same tiers on Anthropic ids. token-diet's
ctx-wire and the skills are enabled too. **`--no-config`** leaves your
config + mcp.json untouched.

Three **official remote MCP servers** are merged into `~/.omp/agent/mcp.json`, all
`type: http`:

| server | endpoint | auth |
|---|---|---|
| `github` | `https://api.githubcopilot.com/mcp/` | PAT (enabled once one is provided / `$GITHUB_TOKEN` is set) |
| `atlassian` | `https://mcp.atlassian.com/v1/mcp/authv2` | OAuth 2.1, on first tool call — nothing stored, enabled by default |
| `context7` | `https://mcp.context7.com/mcp` | `CONTEXT7_API_KEY` header (free tier); registered disabled without one |

Atlassian and Context7 used to ship here as CLI wrappers (`acli`, `ctx7`) on the
argument that an MCP server's tool schemas inline into every system prompt. OMP 17
retired that argument: `tools.xdev` (default on) mounts MCP tools as `xd://` devices
behind a doc budget, so a server costs a mount, not a schema dump. Both are back on
their official endpoints and the wrappers are gone.

**Lean startup context (out of the box).** Every enabled tool's JSON schema is
loaded into the system prompt on *every* request, so the generated config drops
what the team never calls:

- **dev-team** turns off the DAP `debug` tool and the Python/JS `eval` tool — no
  dev-team agent or command uses them (they go through `bash` + the
  `systematic-debugging` skill).

> **Correction (OMP 17).** Earlier versions of this README advertised a
> `tools.discoveryMode: all` + `tools.essentialOverride` trim as the headline win
> ("~29K → ~20K, −31%"). **Those settings were removed in OMP 17.0.0** and are now
> deleted from your config on load, so the trim no longer exists — and the
> installers no longer write them. OMP's replacement needs no configuration:
> `tools.xdev` (default on) mounts non-essential and MCP tools as `xd://` devices
> behind a 48k/10k-char doc budget.

**Corporate proxies (Zscaler / Trend Micro under WSL):** if a TLS-intercepting
proxy breaks certificate checks, the UNIX installers give you two options:

- **Preferred — trust the corporate CA:** `--ca-file=/path/to/corp-root-ca.pem`
  (or `OMP_CA_FILE=…`). Verification stays **on**; node/bun, git, curl/wget, Python
  and **Go tools (Ollama model pulls)** are pointed at your CA via
  `NODE_EXTRA_CA_CERTS`/`SSL_CERT_FILE`/`CURL_CA_BUNDLE`/`GIT_SSL_CAINFO`, and it's
  **persisted to your shell profile** so `omp` and `ollama pull` trust it later too.
  On **WSL you don't even need the .pem** — `--ca-from-windows` exports the Windows
  trust store (incl. the corporate roots) automatically, and the global installer
  **offers it when it detects WSL**. To instead install the corporate CA into WSL's
  **system** trust store (so curl/git/node trust it natively, no env vars), run
  [`scripts/wsl-trust-zscaler.ps1`](scripts/wsl-trust-zscaler.ps1) from **Windows
  PowerShell** — it uses `wsl --user root` (no sudo) and `update-ca-certificates`.
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
omp plugin install openai-compatible@omp-dev-team
omp plugin install datadog@omp-dev-team
```

> **Important — extension modules.** OMP does **not** load extension modules
> (a plugin's `package.json` `omp.extensions`) from a marketplace cache install —
> only skills/commands/agents/rules/MCP surface that way. The plugins whose core
> behavior *is* an extension — **azure-devops-fs** (the `ado` tool),
> **dev-team** (the blocking guards), **openai-compatible** (the
> provider), **token-diet** (read-dedup/context-dedup/context-compress/cache-meter
> + `path-inject`, which puts `~/.local/bin` on OMP's own PATH), and **datadog**
> (`path-inject`, same reason — `pup` lands in `~/.local/bin`) — therefore need
> their installer to run too. The global `install.sh` and each plugin's
> `install.sh`/`install.ps1` mirror those modules into OMP's native
> `~/.omp/agent/extensions/<plugin>/` dir (always discovered, survives config
> resets), so the `ado` tool / guards / provider / PATH fix actually load. A bare
> `omp plugin install <name>@omp-dev-team` alone will show the skill but **not**
> register the extension.

Each plugin ships its own `install.sh` + `install.ps1` (installs that plugin's
tools at their latest versions) — see its README:

- **dev-team** → `bash plugins/dev-team/install.sh --apply-config` (prereq check + config). All-cloud; no local model backend. C# navigation uses OMP's native `lsp` tool, which auto-detects `omnisharp`.
- **copilot-preset** → `bash plugins/copilot-preset/install.sh --apply-config`, then `omp` → `/login` → GitHub Copilot.
- **token-diet** → `bash plugins/token-diet/install.sh` (installs ctx-wire).
- **azure-devops-fs** → `bash plugins/azure-devops-fs/install.sh` (installs the Azure CLI + azure-devops extension, prompts for org/project/PAT, runs `az devops login`), then restart `omp` so the `ado` tool loads.
- **openai-compatible** → `bash plugins/openai-compatible/install.sh --name=litellm --url=http://localhost:4000 --api-key=…` (lists the endpoint's models, writes the provider to `~/.omp/agent/models.yml`), then restart `omp`.
- **datadog** → `bash plugins/datadog/install.sh` (installs the Datadog `pup` CLI + sets up auth; `--with-skills` to also add pup's domain skills).

## Layout

```
install.sh · install.ps1               # global installer (OMP + marketplace + per-plugin prompts)
.claude-plugin/marketplace.json        # catalog (pluginRoot ./plugins)
plugins/
  dev-team/         agents/ skills/ commands/ rules/ extensions/ .mcp.json
                    config.snippet.yml · install.sh · install.ps1
                    skills/dev-team-knowledge/  (registries, rubrics, pricing)
  copilot-preset/   config.snippet.yml · pricing.md · skills/ · install.{sh,ps1}
  token-diet/       .mcp.json · rules/ · skills/ · install.{sh,ps1}
  azure-devops-fs/  extensions/ (ado.ts + lib/az.ts) commands/ skills/ rules/ knowledge/ · install.{sh,ps1}
  openai-compatible/  extensions/ (openai-provider.ts) · skills/ · install.{sh,ps1}
  datadog/          extensions/ (path-inject.ts) · skills/ (umbrella) · install.{sh,ps1}
```

Each plugin's extensions load from its own `package.json` `omp.extensions`; the
guard extensions resolve their data relative to the plugin (so they work
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

Verified end-to-end and in CI (Linux/macOS/Windows — see
[`.github/workflows/installers.yml`](.github/workflows/installers.yml)): all
`install.sh` pass `bash -n`; all `install.ps1` parse under PowerShell 7; all
manifests are valid JSON; the 8 dev-team extensions (plus the token-diet,
azure-devops-fs, openai-compatible, and datadog extension modules) compile under `bun`; ctx-wire
and OMP install via the exact commands the scripts use; and all six
plugins install through real OMP on each OS (`omp plugin marketplace add ./` →
`omp plugin install <name>@omp-dev-team`).

## Credits

- `dev-team` ports [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `token-diet` bundles [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire) and [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman).
- `azure-devops-fs` mirrors the "GitHub as a filesystem" idea from [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
