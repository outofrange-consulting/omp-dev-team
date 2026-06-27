# omp-dev-team for GitHub Copilot CLI

> 🌐 **English** · [Français](README.fr.md)

The [omp-dev-team](../README.md) experience — an agentic **dev-team**, aggressive
**token-diet**, and **Datadog** observability — rebuilt around the idioms of the
[**GitHub Copilot CLI**](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
instead of Oh-My-Pi. Same shape, native to `copilot`.

A global installer ([`install.sh`](install.sh) / [`install.ps1`](install.ps1))
installs the Copilot CLI and then **offers each component as a checkbox** —
install any subset.

| Component | What it does | Copilot CLI surface |
|---|---|---|
| **dev-team** | Orchestrator + workflow agents (`specs → plan → build → review → pr`) and critic agents; a **forced plan gate** (source edits blocked until scoped/planned) + review gate, path/freeze/spec/destructive guards; the `dt` gate CLI. | **custom agents** (`.agent.md`), a **`preToolUse` hook**, **`copilot-instructions.md`** |
| **token-diet** | `ctx-wire` (transparent shell-output compression + secret scrub), **codebase-memory-mcp** (symbol/call-graph queries instead of grep+read), a `postToolUse` output-compression hook, and caveman/yagni discipline. | **PATH shims**, **MCP server**, a **`postToolUse` hook**, instructions |
| **datadog** | Datadog from the terminal via the [`pup`](https://github.com/DataDog/pup) CLI (logs, metrics, traces, monitors, incidents, SLOs, CI/LLM observability). | a **`datadog` agent** driving `pup` |

## Why a port (the mapping)

Copilot CLI has no plugin marketplace, no user-defined slash commands, and no
in-process extensions. It *does* have four customization surfaces, and the port
maps onto exactly those:

| omp-dev-team (Oh-My-Pi) | GitHub Copilot CLI |
|---|---|
| Plugins / marketplace | An **installer** that writes into `~/.copilot/` + the repo's `.github/` |
| Agents (orchestrator + specialists) | **Custom agents** — `.agent.md` in `~/.copilot/agents/` |
| Slash commands `/specs /plan /build /pr` | The same agents, invoked with **`/agent <name>`** |
| Blocking guard extensions (plan-gate, …) | A **`preToolUse` hook** (`.github/hooks/*.json`) that denies/allows tool calls |
| `/scope`, `/plan-approve`, `/freeze`, … | The **`dt` CLI** (Copilot CLI has no custom slash commands) |
| Output-compression extensions | A **`postToolUse` hook** (`modifiedResult`) |
| Rules / operating manual | **`.github/copilot-instructions.md`** |
| codebase-memory-mcp / GitHub MCP | **MCP servers** in `~/.copilot/mcp-config.json` |
| Model tiers (copilot-preset) | `/model` + each agent's `model:` frontmatter |

## Quick start

Prerequisites: **Node.js ≥ 22** (the Copilot CLI requirement) and an active
**GitHub Copilot** subscription.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team/copilot-cli
bash install.sh                 # Linux/macOS   (-y for non-interactive)
#   pwsh -File install.ps1      # Windows
```

The installer:

1. installs/updates the **GitHub Copilot CLI** (`npm i -g @github/copilot`, or
   Homebrew/winget/the install script),
2. asks, per component (dev-team / token-diet / datadog), whether to install it,
3. installs each selected component's agents into `~/.copilot/agents`, its hook
   scripts into `~/.copilot/<component>/`, merges MCP servers into
   `~/.copilot/mcp-config.json` (**existing servers preserved**), and installs the
   `dt` CLI,
4. offers to **arm the dev-team guards in the current repo** (`dt init`).

Then: open a new shell, run `copilot`, `/login` (GitHub Copilot), pick a model
with `/model`, and use the agents with `/agent <name>`.

## The dev-team flow

Copilot CLI loads hooks from the **project** (`.github/hooks/`), so the blocking
guards are armed per-repo. In any repo:

```sh
dt init            # writes .github/hooks/*.json + .github/copilot-instructions.md
```

Then the enforced pipeline (the `preToolUse` hook blocks source edits / commits
until each gate is satisfied):

```sh
dt scope                 # pre-analysis (or: dt scope --trivial | --complex)
copilot                  # /agent specs   → write .feature acceptance criteria
                         # /agent plan     → the plan is the review artifact
dt plan-approve          # human sign-off → unlocks source edits
                         # /agent build    → implement; tests required
                         # /agent review   → critics on the staged diff
dt review-approve        # unlocks `git commit`
                         # /agent pr        → open the PR
dt status                # show the gate; dt reset re-arms for the next task
```

`dt help` lists every command (`freeze`/`unfreeze`, `careful on|off`,
`allow-feature-edits`/`protect-features`, …).

### What the guards enforce (ported 1:1 from the OMP extensions)

- **plan-gate** — edits to production *source* are denied until the task is
  scoped and (if non-trivial) `dt plan-approve` has run. Docs/config/specs/tests
  are never gated.
- **path-guard** — writes to `.env`, `*.pem`, `*.key`, `*secret*`, `id_rsa`, … are
  denied (file tools **and** shell redirection/`tee`/`sed -i`/`cp`/`mv`).
- **freeze-guard** — `dt freeze '<glob>'` locks paths against edits.
- **spec-guard** — editing an existing `.feature` BDD spec is denied (fix the
  code, not the test); authoring a new spec is fine.
- **destructive-guard** — in `dt careful on` mode, destructive shell commands
  (`rm -rf /`, `git push --force`, `drop table`, `mkfs`, …) are denied; a curated
  safe-list (`rm -rf node_modules`, …) is allowed.
- **review-gate** — `git commit` is denied until the staged diff is
  `dt review-approve`'d (bypass with an explicit `--no-verify`).

> **Honesty.** The guards are out-of-tree, advisory-grade enforcement keyed on
> per-repo state — rails to keep the agent and the human on the pipeline, **not a
> hard sandbox**. An agent running arbitrary shell could reach the state dir. Same
> stance as upstream.

## Models (tiers)

Recommended Copilot models per role (set with `/model`, or per agent via the
`model:` frontmatter): `claude-haiku-4.5` (cheap, high-volume critics),
`claude-sonnet-4.6` (balanced default — orchestrator, plan, build, most critics),
`claude-opus-4.8` (deep — security/architecture, the plan step of a complex task).
Put the expensive thinking into **scope/plan**, not the build.

## token-diet

```sh
bash packs/token-diet/install.sh    # ctx-wire + codebase-memory-mcp + the hook
```

- **ctx-wire** installs PATH shims (`~/.local/bin`) that transparently compress
  shell output and scrub secrets — CLI-agnostic, works the same under `copilot`.
- **codebase-memory-mcp** is registered into `~/.copilot/mcp-config.json` so you
  query symbols/call-graphs instead of grepping + reading whole files. It indexes
  the repos under the sources root you pick.
- The **`postToolUse` hook** scrubs secrets, collapses blank runs, and
  head/tail-truncates very large *non-shell* tool output (armed per-repo by
  `dt init`). Lossy truncation is always marked.
- Append `~/.copilot/token-diet/instructions/token-diet.md` to a repo's
  `copilot-instructions.md` for the caveman (terse) + yagni (minimal-code)
  discipline. `dt init` does this automatically when both packs are installed.

## datadog

```sh
bash packs/datadog/install.sh       # installs pup + the datadog agent
```

`/agent datadog` drives the `pup` CLI. Authenticate with `pup auth login` (OAuth)
or `DD_API_KEY`/`DD_APP_KEY`/`DD_SITE`.

## Layout

```
copilot-cli/
  install.sh · install.ps1            # global installer (Copilot CLI + per-component checkboxes)
  lib/merge-json.mjs                  # non-clobbering JSON merge (mcp-config.json)
  packs/
    dev-team/
      agents/*.agent.md               # orchestrator, specs, plan, build, review, pr, + critics
      hooks/scripts/                  # common.mjs + pre-tool-use.mjs (the blocking guard)
      instructions/copilot-instructions.md
      dt.mjs                          # the gate CLI + `dt init`
      install.sh · install.ps1
    token-diet/
      hooks/scripts/post-tool-use.mjs # output compression + secret scrub
      mcp/codebase-memory-mcp.json    # MCP snippet (merged at install)
      instructions/token-diet.md
      install.sh · install.ps1
    datadog/
      agents/datadog.agent.md
      install.sh · install.ps1
```

## Corporate proxies (Zscaler / Trend Micro)

The Unix installer mirrors the OMP one: `--ca-file=/path/to/corp-root-ca.pem`
(verification stays on, persisted to your profile), `--ca-from-windows` on WSL
(auto-exports the Windows trust store), or the `--insecure-tls` escape hatch.

## Relationship to the Oh-My-Pi marketplace

This tree is **self-contained** and additive — it does not touch the OMP plugins
in [`../plugins`](../plugins). The guard logic and the ctx-wire filter pack are
ported from / reused by the OMP `dev-team` and `token-diet` plugins, so the two
stay in sync.
