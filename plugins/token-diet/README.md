# token-diet

> 🌐 **English** · [Français](README.fr.md)

**v2.0.0 — refocused.** This plugin used to be a runtime layer over OMP:
read dedup, context dedup, a prompt-cache meter, a "lean tool surface". OMP 17.x
ships all of it. What is left is the narrow set of things the harness genuinely
does not do — and nothing here duplicates it.

| Layer | What | Why it survives |
|---|---|---|
| **ctx-wire filters** (4) | EN+FR filters for `dotnet publish` / `pack` / `run` / `tool` | OMP truncates *mechanically* (tail window, column cap, artifact spill). Only these know a 20 KB all-green `dotnet publish` collapses to one artifact line — and only these know it in French. OMP's own Rust filters already own `git` and `dotnet build\|test\|restore\|format`, so we ship neither. |
| **caveman** (skill) | terse, fragment-style **output**, on demand | The only lever aimed at **output** tokens. Nothing in OMP — or in upstream agentic-dev-team — touches what the model writes. Costs only its name + description until invoked. |
| **path-inject** (extension) | prepends `~/.local/bin` to `PATH` inside the OMP process | OMP spawns bash non-login/non-interactive, so `~/.profile` is never sourced and a freshly installed ctx-wire shim is invisible until you open a new terminal. 32 lines, no hooks, no message mutation. |
| **context-compress** (extension) | protect-masked prose shrink of OLD messages | **OFF by default, opt-in.** Kept as an instrumented experiment, not a feature — see the warning below. |
| **token-tools** (rule) | ~15 lines, `alwaysApply` | ctx-wire is transparent; `read`/`grep`/`astEdit` still beat raw shell; edit symbols structurally. |
| **provider isolation + native settings** | `config.snippet.yml` | `disabledProviders` plus the handful of OMP settings that actually pay off today (below). |

## What OMP does natively (so this plugin doesn't)

| Native | Default | Replaced from this plugin |
|---|---|---|
| `compaction.supersedeReads` | **on** | `read-dedup` + `context-dedup`. And native is *better*: it keeps the **newest** read and blanks the older; ours blocked the newer and forced the model onto stale bytes. |
| `compaction.dropUseless`, `pruneToolOutputs` | **on** / built in | the rest of the dedup story |
| `shellMinimizer` Rust filters | **on** | our `git-status` / `dotnet-build` / `dotnet-test` / `dotnet-restore` filters |
| statusline `cost` / `cache_read` / `cache_write` / `cache_hit` / `context_pct` / `usage` | segments | `cache-meter` and `/cache-health` — and the installer's fork of OMP's own status-line renderer, which was broken anyway |
| `secrets.enabled` + `~/.omp/agent/secrets.yml` | off → **we turn it on** | the token-redaction stage of the old `acli` filter — and it covers the case a command filter never could: secrets arriving via `read .env` or an MCP result |
| `tools.xdev` | **on** | `tools.discoveryMode` / `tools.essentialOverride` (removed in OMP 17.0.0 and now silently deleted from your config on load) and the `mcp-as-cli-skill-creator` skill built on their premise |
| `lsp` + built-in `omnisharp` | auto | any C#-specific navigation tooling this plugin used to install |

**Design rule that follows from this:** do not build a plugin-side context
transform. Rewriting *old* messages mutates the prefix the provider KV-caches,
and cached input is ~10× cheaper than fresh input — a cache bust costs more than
the bytes it saves.

## Where the removed pieces went

| Removed | Now |
|---|---|
| `atlassian` skill + the `acli` install/auth + `acli.toml` | the **official Atlassian remote MCP server** (`https://mcp.atlassian.com/v1/mcp/authv2`, OAuth), wired by the repo-root installer |
| `context7` skill + the `ctx7` CLI install | the **official Context7 remote MCP server** (`https://mcp.context7.com/mcp`, `CONTEXT7_API_KEY` header), wired by the repo-root installer |
| `yagni` skill | **deleted** |
| `mcp-as-cli-skill-creator` skill | deleted — its premise ("MCP schemas cost context, wrap them as CLIs") died with `tools.xdev` |
| `read-dedup`, `context-dedup`, `cache-meter` extensions, `/cache-health` | deleted — native (table above) |
| `context-mode` plugin install | deleted — OMP's shellMinimizer + artifact spill cover it |

## Install

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh    # then restart omp
```

The installer: installs/updates ctx-wire and its PATH shims, merges the four
filters into `~/.config/ctx-wire/filters.toml`, installs `ast-grep`, merges
`config.snippet.yml` per top-level key, and mirrors `extensions/` + `rules/` into
`~/.omp/agent`. Flags: `--no-update`, `--no-config`, `--no-cleanup`,
`--insecure-tls`, `--ca-file=…`.

## How it's wired into OMP

- **ctx-wire** → `ctx-wire shims install` drops transparent wrappers into
  `~/.local/bin` (first on PATH, inherited by OMP's bash tool), so the agent runs
  commands with **no prefix** and their output is filtered before it hits
  context. Full logs stay on disk; `ctx-wire gain` shows the savings,
  `ctx-wire doctor` verifies. **Restart required**: an OMP process already
  running when the installer executes keeps its old PATH; the installer probes a
  fresh login shell and warns when this session is stale. (`path-inject` closes
  the same gap from inside the process for future sessions.)
- **Filters** → only `dotnet publish`/`pack`/`run`/`tool`. `git` and
  `dotnet build|test|restore|format` are handled by OMP's own Rust minimizer, on
  by default, so shipping ours would be two passes over the same bytes.
  **The locale gap is the real reason this pack exists**: OMP's `LANG=C.UTF-8`
  hardening is **Windows-only**, so on Linux/macOS a French locale reaches
  git/dotnet and the native English filters silently miss. The cheapest fix is
  to pin the locale (`DOTNET_CLI_UI_LANGUAGE=en`, `LC_MESSAGES=C`) — see
  `ctx-wire/README.md`. No Romanian: git and .NET ship no `ro` translation.
- **Extensions** → mirrored into `~/.omp/agent/extensions/token-diet`, because
  OMP does not load extension entry points from a marketplace install.
  `path-inject` is always on and configuration-free. `context-compress` is
  **off** unless you set `TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full`: at `safe`
  its whole job (strip ANSI, collapse whitespace) is already done at the source,
  and its `keepRecent` window *slides*, so every turn one more message flips
  from pristine to compressed — a recurring byte change inside the already-sent
  prefix, which is exactly what busts the prompt cache. Turn it on only after
  measuring your cache-read ratio. Pure logic lives in `extensions/lib` and is
  unit-tested by `bun scripts/extensions.test.ts`.
- **token-tools rule** → `rules/token-tools.md` is `alwaysApply: true`, so it is
  in the system prompt of every request and is deliberately ~15 lines. OMP's
  plugin rule provider only auto-discovers `rules/*.md` inside *configured*
  extension package roots, and a marketplace install isn't one — so the
  installers copy it to `~/.omp/agent/rules/token-diet-*.md`, which the native
  provider (priority 100) always scans.
- **config.snippet.yml** → merged per top-level key via `scripts/lib/cfg.sh`, so
  running the repo-root installer and this one cannot produce duplicate
  top-level YAML keys. It sets `secrets.enabled`,
  `tools.artifactSpillThreshold: 10`, `bashInterceptor.enabled`,
  `shellMinimizer.sourceOutlineLevel: aggressive`, `compaction.idleEnabled`,
  `read.summarize.prose`, the skills/commands toggles, and `disabledProviders`
  (`~/.claude/plugins`, `~/.codex`, `~/.gemini`, `~/.cursor`,
  `~/.codeium/windsurf`, `~/.config/opencode`, `.clinerules`). The `github`
  provider is deliberately left enabled so copilot-preset keeps working.
- **Cost / cache visibility** → native, no plugin:
  ```yaml
  statusLine:
    preset: custom
    rightSegments: [cost, cache_hit, cache_write, context_pct, usage]
  ```
- **Context-file heads-up** → without `~/.omp/agent/AGENTS.md`, OMP falls back
  to Claude Code's own user-scope `CLAUDE.md` and reads it verbatim, including
  Claude-Code-only advice
  (e.g. a ctx-wire-injected block telling the agent to prefer raw shell over
  built-in tools — right for Claude Code, wrong for OMP). The installers warn
  once when this applies.

## Notes

- Pairs naturally with **copilot-preset** (cheap per-token models) — fewer tokens
  × cheaper tokens.
- Ships no MCP server and no LSP. C# navigation and semantics go through OMP's
  native `lsp` tool, which has `omnisharp` as a built-in default for `.cs`/`.csx`.
- Independent of the other plugins; install only what you want.
- CI runs both proofs: `python3 ctx-wire/scripts/verify-filters.py ctx-wire/filters.d`
  (23/23) and `bun scripts/extensions.test.ts`.
