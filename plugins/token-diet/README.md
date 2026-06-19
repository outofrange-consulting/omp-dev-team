# token-diet

> 🌐 **English** · [Français](README.fr.md)

Aggressive **token reduction** for OMP dev teams. Bundles three best-in-class
external token savers and wires them into OMP the native way — on top of what OMP
already does (compaction, `astGrep`/`summarizeCode`, provider prompt caching), not
in place of it.

| Layer | What | Win | Upstream |
|---|---|---|---|
| **ctx-wire** | transparent CLI proxy that filters command **output** + scrubs secrets (full logs kept on disk); **EN+FR** filter overrides for `git status` + `dotnet build`/`test` (VSTest & MTP)/`restore`/`run`/`tool` | big cuts on `git`/build/test/lint noise | [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire) |
| **context-mode** | native OMP plugin that **sandboxes tool output** and indexes it (FTS5/BM25, language-agnostic) — keeps raw payloads out of context + survives compaction | ~98% on giant/unstructured output; any locale (incl. ro) | [mksglu/context-mode](https://github.com/mksglu/context-mode) |
| **CodeGraph** | MCP symbol/call graph — query instead of grep+read | ~96% on "who calls X / impact / architecture" | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) |
| **context7** | MCP library docs lookup — up-to-date API docs on demand | eliminates stale-knowledge hallucinations on library APIs | [upstash/context7](https://github.com/upstash/context7) |
| **caveman** | terse, fragment-style **output** (on demand) | ~65% output tokens | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | write **less code** — YAGNI / laziest-senior-dev (on demand) | ~80–94% less code; fewer tokens now + every future turn | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **Provider isolation** | excludes all foreign-tool user configs from OMP context | eliminates agent noise from Claude Code / Codex / Gemini / Cursor / Windsurf / Copilot / OpenCode plugin registries | built-in OMP settings |
| **Lean tool surface** | `tools.discoveryMode: all` — hides non-essential tool schemas behind OMP's on-demand discovery tool, keeping only the hot path loaded | startup "System tools" ~18K → ~10K (full dev-team startup ~29K → ~20K), no capability lost | built-in OMP settings |
| **C# LSP** | `csharp-ls` wired as OMP-native language server | go-to-definition, references, diagnostics on `.cs`/`.csx` | [razzmatazz/csharp-language-server](https://github.com/razzmatazz/csharp-language-server) |

## Install

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installs ctx-wire + codegraph, indexes your repos,
                                     # and turns everything on. Restart omp afterwards.
```

**Active by default after `install.sh`** — no manual flags: ctx-wire shims compress
command output, the CodeGraph MCP server is enabled, and the skills are turned on.
`install.sh` prompts for the **root of your sources** (a directory of many repos)
and indexes each git repo it finds (`--sources-root=PATH`, `--depth=N`).

## How it's wired into OMP

- **ctx-wire** → installed by `install.sh`, then **`ctx-wire shims install`** drops
  transparent wrappers into `~/.local/bin` (first on PATH, inherited by OMP's bash
  tool) so the agent runs commands normally — **no prefix** — and their output is
  filtered + secret-scrubbed before it hits context (full logs kept on disk).
  (`ctx-wire init claude` only wires Claude Code, not OMP, so we use shims.)
  `ctx-wire gain` shows savings; `ctx-wire doctor` verifies; `ctx-wire mcp-wrap` can also compress
  MCP-server output. Replaces the earlier RTK integration (RTK is also English-only,
  so it offered no localization advantage).
  **Multilingual filters** → `install.sh` merges EN+FR overrides
  (`ctx-wire/filters.d/`) for `git status` + `dotnet build`/`test` (VSTest **and**
  Microsoft.Testing.Platform)/`restore`/`run`/`tool` into
  `~/.config/ctx-wire/filters.toml`, so the same compaction fires in `fr_*`
  locales (FR strings taken verbatim from git/MSBuild/VSTest localization). Only
  git+dotnet are localized: every other ctx-wire filter is either structural
  (grep, git-log, ls) or wraps an English-only toolchain (npm/cargo/go/…).
  **No Romanian** — git and .NET ship no `ro` translation, so they emit English
  in a `ro_RO` locale; Romanian only appears in *data*, handled by context-mode.
  See `ctx-wire/README.md`.
- **context-mode** → `omp plugin install context-mode` (run by `install.sh`,
  `--no-context-mode` to skip). A native OMP plugin on the
  `tool_call`/`tool_result`/`session_start`/`session_before_compact` hooks that
  sandboxes tool output and indexes it with language-agnostic FTS5/BM25 — the
  locale-agnostic safety net for any-language output (incl. Romanian) and for
  session continuity across compaction. Layers on top of ctx-wire's deterministic
  collapses, not in place of them. It also compresses **MCP** tool output (it hooks
  `tool_result`), so the verbose Atlassian/Miro/GitHub MCP JSON is reduced too —
  the ctx-wire shims only see shell commands, not MCP. For self-defined MCP servers
  you can additionally use `ctx-wire mcp-wrap --compress`; see `ctx-wire/README.md`.
- **acli** → the official **Atlassian CLI** (Jira/Confluence/Bitbucket), installed to
  `~/.local/bin` by `install.sh` (`--no-acli` to skip; re-run to update — versions are
  supported ~6 months). Prefer the **Atlassian MCP** for structured reads; use `acli`
  for bulk/scripted writes. Its output is English/structural — the bundled
  `ctx-wire/filters.d/acli.toml` compacts it and redacts bare `ATATT…` API tokens
  (ctx-wire already scrubs GitHub/ADO/Atlassian tokens in header/URL/`key=value` form).
- **CodeGraph** → an MCP server (`.mcp.json`, `codegraph serve --mcp`, **enabled by
  default**) exposing `codegraph_search/node/callers/callees/explore/impact/files/status`.
  See `skill://codegraph`. Auto-syncs on file changes.
- **skills** → `install.sh` appends `config.snippet.yml` to `~/.omp/agent/config.yml`
  enabling skill commands and applying provider isolation. `--no-config` to skip.
- **context7** → CLI mode (`ctx7 library` / `ctx7 docs` via bash — no MCP process).
  `install.sh` installs the `ctx7` CLI globally. The bundled `context7` skill
  (`skill://context7`) instructs the agent to fetch current docs automatically
  whenever a library, framework, or API is involved.
- **Lean tool surface** → `config.snippet.yml` sets `tools.discoveryMode: all` with
  an `essentialOverride` hot path (`read, bash, edit, write, find, search, task,
  todo`). OMP otherwise inlines every tool's JSON schema into the system prompt on
  every request (~18K with dev-team); discovery mode hides the non-essential ones
  behind the built-in `search_tool_bm25` discovery tool, so they cost nothing until
  used. Drops startup "System tools" to ~10K. Widen the always-loaded set (e.g. add
  `ast_grep`) via `tools.essentialOverride`; set `discoveryMode: auto` to only hide
  MCP tools past 40, or `off` to disable.
- **Provider isolation** → `config.snippet.yml` sets `disabledProviders` +
  `enableClaudeUser/Project/CodexUser: false` so OMP only loads its own plugins and
  project-level `AGENTS.md`/`CLAUDE.md`. Excluded: `~/.claude/plugins`, `~/.codex`,
  `~/.gemini`, `~/.cursor`, `~/.codeium/windsurf`, `~/.copilot`, `~/.config/opencode`,
  `.clinerules`. Existing users who re-run `install.sh` get a `disabledProviders`
  block appended without touching other settings.
- **C# LSP** → `install.sh` installs `csharp-ls` via `dotnet tool install -g csharp-ls`
  (if .NET SDK present) and writes `~/.omp/agent/lsp.json` to register it for `.cs`/
  `.csx` files. OMP auto-activates it when a `.sln`/`.slnx`/`.csproj` is detected.
- **caveman** → a native OMP skill (`/caveman`, levels lite/full/ultra) rather
  than the upstream installer, so it's first-class in OMP. See `skill://caveman`.
- **yagni** → a native OMP skill (`/yagni`, levels lite/full/ultra/off) porting
  the ponytail "laziest senior dev" YAGNI discipline: a *do-I-even-need-this*
  ladder + review/audit/debt modes. Lazy ≠ negligent — security/validation/data-
  loss/a11y/tests are never cut (and it won't edit `.feature` specs to dodge
  work). See `skill://yagni`.

## What OMP already does (so you don't double up)

Compaction/handoffs (history summarization), native AST tools (`astGrep`,
`astEdit`, `summarizeCode`, `blockRangeAt`), and provider prompt/context caching.
This plugin fills the remaining gaps: raw command output, persistent cross-file
symbol graph, and verbose model output. See `skill://token-diet` for the full
decision guide.

## Notes

- Pairs naturally with **copilot-preset** (cheap per-token models) — fewer tokens
  × cheaper tokens.
- The CodeGraph entry previously sitting (disabled) in `dev-team/.mcp.json` is
  now centralized here with the correct `serve --mcp` invocation.
- Independent of the other plugins; install only what you want.
