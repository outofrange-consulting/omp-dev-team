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
| **codebase-memory-mcp** | MCP symbol/call knowledge graph (158 langs, embedded Hybrid LSP) — query instead of grep+read | ~99% on "who calls X / impact / architecture" | [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) |
| **context7** | MCP library docs lookup — up-to-date API docs on demand | eliminates stale-knowledge hallucinations on library APIs | [upstash/context7](https://github.com/upstash/context7) |
| **caveman** | terse, fragment-style **output** (on demand) | ~65% output tokens | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | write **less code** — YAGNI / laziest-senior-dev (on demand) | ~80–94% less code; fewer tokens now + every future turn | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **mcp-as-cli-skill-creator** (skill) | a schema-heavy MCP server inlines its whole tool schema into the system prompt every request | turns an MCP / OpenAPI / GraphQL into a thin runtime CLI + on-demand skill, keeping its schema **out of the context window** (the ctx7/acli pattern, generalized) | native OMP skill |
| **read-dedup** + **context-dedup** | re-reads of unchanged files + byte-identical repeated blocks inflate **input** | LOSSLESS, on: re-read → stub; identical blocks collapsed before each call | caveman-code's "Read Dedup", reimplemented on OMP's `tool_call`/`context` hooks |
| **context-compress** | old **prose** context stays verbose every turn | protect-masked prose shrink of old messages — code/paths/numbers byte-identical (`safe` on by default; `lite`/`full` opt-in) | quality-preserving take on [caveman-code](https://github.com/JuliusBrussee/caveman-code)'s LLMLingua/Provence |
| **cache-meter** | the prompt-cache savings you *think* you get are unmeasured — and a prefix-mutating transform can silently bust them | READ-ONLY, on: a live **statusline** (`td $cost cache N% churn N%`, ⚠ on risk) + `/cache-health` for the full read-rate / churn / cost / thinking-share / provider-quota breakdown; **warns** when `lite`/`full` compression coincides with high cache churn | OMP per-turn `usage` (`turn_end`) + `after_provider_response` headers + `ui.setStatus` |
| **Provider isolation** | excludes all foreign-tool user configs from OMP context | eliminates agent noise from Claude Code / Codex / Gemini / Cursor / Windsurf / Copilot / OpenCode plugin registries | built-in OMP settings |
| **Lean tool surface** | `tools.discoveryMode: all` — hides non-essential tool schemas behind OMP's on-demand discovery tool, keeping only the hot path loaded | startup "System tools" ~18K → ~10K (full dev-team startup ~29K → ~20K), no capability lost | built-in OMP settings |
| **C# LSP** | `csharp-ls` wired as OMP-native language server — used for precise C# semantics that the knowledge graph can't give (rename, exact references, live diagnostics, hover) | go-to-definition, references, diagnostics on `.cs`/`.csx` | [razzmatazz/csharp-language-server](https://github.com/razzmatazz/csharp-language-server) |

## Install

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installs ctx-wire + codebase-memory-mcp, indexes
                                     # your repos, and turns everything on. Restart omp.
```

**Active by default after `install.sh`** — no manual flags: ctx-wire shims compress
command output, the codebase-memory-mcp MCP server is enabled, and the skills are turned on.
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
  **Restart required**: shims land in `~/.local/bin`; an OMP process already
  running when `install.sh` executes keeps its old PATH and won't see them
  until you restart OMP (re-running the installer again does not help). The
  installer now probes a fresh non-interactive shell right after `ctx-wire
  shims install` and prints an explicit warning if this session is stale.
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
- **token-tools rule** → `rules/token-tools.md` (`alwaysApply: true`) is the
  agent-facing routing guidance for everything on this page: run commands with
  no prefix, prefer codebase-memory-mcp over grep/glob/Read for structural
  questions, `csharp-ls` for precise C# semantics, `astEdit` over whole-file
  rewrites, and how to recognize a stale/pre-restart shim session. OMP's rule
  provider only auto-discovers `rules/*.md` inside *configured* extension
  package roots, and a bare marketplace install of this plugin isn't one — so
  `install.sh`/`install.ps1` copy it into `~/.omp/agent/rules/token-diet-*.md`
  (same workaround the `extensions/` mirror below already uses), where OMP's
  native provider always scans it.
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
  supported ~6 months). **acli is our go-to for Atlassian** — for both reads and
  writes, instead of the Atlassian MCP. `install.sh` also offers to run
  `acli jira auth login` when interactive. Its output is English/structural — the
  bundled `ctx-wire/filters.d/acli.toml` compacts it and redacts bare `ATATT…` API
  tokens (ctx-wire already scrubs GitHub/ADO/Atlassian tokens in header/URL/`key=value` form).
- **codebase-memory-mcp** → an MCP server (`.mcp.json`, binary launched in MCP mode,
  **enabled by default**) exposing `search_graph`/`search_code`/`get_code_snippet`/
  `trace_path`/`get_architecture`/`query_graph`/`detect_changes`/`get_graph_schema`/
  `index_repository`/`index_status`/`list_projects`/`delete_project`/`manage_adr`/
  `ingest_traces` (158 languages, embedded Hybrid LSP). See `skill://codebase-memory`.
  Auto-syncs on file changes after the first index. For precise C# semantics the graph
  can't answer (rename, exact references, live diagnostics, hover) it defers to the
  `csharp-ls` LSP — see the **C# LSP** row.
- **skills** → `install.sh` appends `config.snippet.yml` to `~/.omp/agent/config.yml`
  enabling skill commands and applying provider isolation. `--no-config` to skip.
- **context7** → CLI mode (`ctx7 library` / `ctx7 docs` via bash — no MCP process).
  `install.sh` installs the `ctx7` CLI globally. The bundled `context7` skill
  (`skill://context7`) instructs the agent to fetch current docs automatically
  whenever a library, framework, or API is involved.
- **mcp-as-cli-skill-creator** → a native skill (`skill://mcp-as-cli-skill-creator`)
  that **generalizes the `ctx7`/`acli` move**: given an MCP server (or OpenAPI /
  GraphQL endpoint), it generates a thin runtime **CLI** (`~/.local/bin/<tool>`,
  one subcommand per operation) plus a companion **skill doc**, and keeps the
  server **out of `.mcp.json`**. The capability stays a bash call away while its
  JSON schema leaves the system prompt — directly serving the lean tool surface
  (`discoveryMode: all`). Ships a `references/cli-template.ts` skeleton (MCP-stdio
  JSON-RPC handshake + arg parsing + compact JSON out). Best for schema-heavy,
  call-light servers; not for hot-path or streaming/stateful tools.
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
- **Context-file heads-up** → if you don't yet have `~/.omp/agent/AGENTS.md`,
  OMP falls back to reading `~/.claude/CLAUDE.md` verbatim at user scope,
  including any Claude-Code-only advice it carries (e.g. a ctx-wire-injected
  block telling the agent to prefer raw shell over built-in tools — right for
  Claude Code, wrong for OMP). `install.sh`/`install.ps1` print a one-time
  warning when this applies; consider a native `AGENTS.md` with just the
  conventions that actually apply to OMP.
- **C# LSP** → `install.sh` installs `csharp-ls` via `dotnet tool install -g csharp-ls`
  (if .NET SDK present) and writes `~/.omp/agent/lsp.json` to register it for `.cs`/
  `.csx` files. OMP auto-activates it when a `.sln`/`.slnx`/`.csproj` is detected. It
  stays alongside codebase-memory-mcp on purpose: the knowledge graph answers
  structural/whole-repo questions (incl. C#, via the embedded Hybrid LSP), while
  `csharp-ls` is a full language server reserved for the C#-only needs the graph can't
  cover — exact find-all-references, rename, live diagnostics/type errors,
  hover/signature help, completion.
- **caveman** → a native OMP skill (`/caveman`, levels lite/full/ultra) rather
  than the upstream installer, so it's first-class in OMP. See `skill://caveman`.
- **yagni** → a native OMP skill (`/yagni`, levels lite/full/ultra/off) porting
  the ponytail "laziest senior dev" YAGNI discipline: a *do-I-even-need-this*
  ladder + review/audit/debt modes. Lazy ≠ negligent — security/validation/data-
  loss/a11y/tests are never cut (and it won't edit `.feature` specs to dodge
  work). See `skill://yagni`.
- **read-dedup / context-dedup / context-compress** → native OMP extensions,
  mirrored into `~/.omp/agent/extensions/token-diet` by `install.sh` (OMP doesn't
  load extensions from marketplace cache installs). The two **dedups are lossless
  and on by default**: read-dedup gates the `read` tool (`tool_call`) so a
  byte-identical re-read of an unchanged file returns a stub instead of the bytes
  (compaction-aware), and context-dedup uses the `context` hook to collapse
  byte-identical large blocks repeated across tool/assistant messages (keeping
  the newest verbatim) — catching duplicates from any source, including
  `bash`/`cat` and MCP. **context-compress runs at `safe` by default**
  (near-lossless: strips ANSI + collapses whitespace only, never drops words) —
  the quality-preserving realization of caveman-code's LLMLingua/Provence context
  transform. A *protect mask* keeps code, paths, numbers and identifiers
  **byte-identical** (the same set you'd hand real LLMLingua-2 as `force_tokens`),
  only prose is touched, and the recency window + every user/system message are
  left untouched. Go further (lossy — drops filler/articles) or disable with
  `TOKEN_DIET_CONTEXT_COMPRESS=lite|full|off`. Pure logic in `extensions/lib`,
  unit-tested by `bun scripts/extensions.test.ts`. Full analysis + the heavier
  real-LLMLingua escalation path: `research/caveman-code.md`.
- **cache-meter** → a **read-only** extension (never mutates a request) that
  accumulates OMP's per-turn `usage` (`turn_end.message.usage`:
  input/output/**cacheRead/cacheWrite**/cost/thinking) plus the provider
  rate-limit headers (`after_provider_response`). It keeps a live footer
  **statusline** via `ctx.ui.setStatus` (`td $<cost> cache <read%> churn <%>`,
  with a ⚠ on cache-bust risk — the always-visible glance at cost/cache health),
  and `/cache-health` prints the full breakdown: prompt-cache **read-rate** and
  **churn**, cumulative **cost**, thinking-token share, context-window %, and
  provider quota. Its point is the closing-the-loop
  check for the rest of token-diet: because `context-compress`/the dedups rewrite
  **old** messages — exactly the stable prefix a provider KV-caches — they can
  *raise* visible-token savings while *busting* the 10×-cheaper cache read. The
  meter **warns** when prefix-mutating compression (`lite`/`full`) coincides with
  high cache churn, so the "CacheAligner" prefix-freeze is only built if the
  numbers actually show a problem (measure first). Off (whole meter) with
  `TOKEN_DIET_CACHE_METER=off`, or silence just the footer line with
  `TOKEN_DIET_CACHE_STATUSLINE=off`; pure math in `extensions/lib/cache-stats.ts`,
  unit-tested. (OMP exposes this usage to extensions today — the older
  "token usage isn't available to hooks" assumption no longer holds.)

## What OMP already does (so you don't double up)

Compaction/handoffs (history summarization), native AST tools (`astGrep`,
`astEdit`, `summarizeCode`, `blockRangeAt`), and provider prompt/context caching.
This plugin fills the remaining gaps: raw command output, persistent cross-file
symbol graph, and verbose model output. See `skill://token-diet` for the full
decision guide.

## Notes

- Pairs naturally with **copilot-preset** (cheap per-token models) — fewer tokens
  × cheaper tokens.
- The code-graph MCP server (formerly CodeGraph) is centralized here as
  codebase-memory-mcp; `dev-team/.mcp.json` carries no code-graph entry.
- Independent of the other plugins; install only what you want.
