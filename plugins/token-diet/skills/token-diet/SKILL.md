---
name: token-diet
description: >-
  How this workspace minimizes LLM token spend. Use when the user asks how to
  reduce tokens/cost, what ctx-wire / codebase-memory-mcp / caveman / yagni are, how to set them up, or
  whether OMP already does X natively.
---

# token-diet — aggressive token reduction for OMP

Three external layers on top of what OMP already does natively. Run
`plugins/token-diet/install.sh` to install them.

## What OMP already does (don't reinvent)

- **Compaction & handoffs** — long sessions get summarized automatically
  (`/compact`, auto-compaction). Keeps history cheap.
- **AST tools** — native `astGrep`, `astEdit`, `summarizeCode`, `blockRangeAt`:
  structural search/edit and file summaries without dumping whole files.
- **Prompt/context caching** — stable system prompts & reused context are cached
  by the provider (cached input is ~10× cheaper on Copilot/Anthropic).

## What this plugin adds (the gaps)

| Tool | Fills the gap of… | Win |
|---|---|---|
| **ctx-wire** | command **output** is dumped raw into context (and may leak secrets) | filtered + secret-scrubbed `git/build/test/lint` output (full logs kept on disk) |
| **codebase-memory-mcp** (MCP) | no persistent cross-file **symbol/call graph** | ~99% fewer tokens for "who calls X / impact / architecture" vs grep+read; 158 langs |
| **caveman** (skill) | agent **output** is verbose prose | ~65% fewer output tokens, on demand |
| **yagni** (skill) | agent writes **too much code** (bloat/over-engineering) | ~80–94% less code → fewer output now + fewer input tokens every future turn |
| **read-dedup** + **context-dedup** (extensions) | unchanged files re-read, and identical big blocks repeated, **inflate input** | LOSSLESS, on by default: re-reads return a stub; byte-identical repeated blocks collapsed before each call |
| **context-compress** (extension) | old **prose** context stays verbose every turn | protect-masked prose shrink of OLD messages — code/paths/numbers kept byte-identical (`safe` on by default; `lite`/`full` lossy/opt-in; `off` to disable) |

## Decision guide

- Running shell commands? → output is transparently compressed + secret-scrubbed
  by `ctx-wire` (no prefix; `ctx-wire gain` shows savings).
- "Where is X / who calls X / what breaks if I change X / how does this module
  fit together?" → use `skill://codebase-memory` (the codebase-memory-mcp tools:
  `search_graph` / `trace_path` / `get_architecture` / `detect_changes`).
- Precise C# semantics (rename, exact references, diagnostics, hover) the graph
  can't answer → the `csharp-ls` LSP (auto-active on `.sln`/`.csproj`).
- Editing one known file / reading docs/prose → plain `Read` + `astEdit`.
- Want terse, fragment-style replies to save output tokens → `/caveman`
  (`skill://caveman`).
- Want the agent to **write minimal code** (YAGNI, no over-engineering) or to
  review a diff for bloat → `/yagni` (`skill://yagni`).
- Don't re-read an unchanged file to "refresh" — it's **deduped** (a stub is
  returned; the earlier read is still in context). Same for re-pasting/echoing
  the same large output: byte-identical repeated blocks are collapsed each call.
- Want to *see* live cost / prompt-cache health (read-rate, churn, $, thinking
  share, provider quota) — or check whether `lite`/`full` compression is busting
  the cached prefix → run **`/cache-health`** (the read-only `cache-meter`).
- Verbose **old prose** context is already squeezed at `safe` by default
  (near-lossless; code/paths/numbers byte-identical, recency window untouched).
  For more, set `TOKEN_DIET_CONTEXT_COMPRESS=lite|full` (lossy — drops
  filler/articles), or `off` to disable.

## Setup (once per machine / project)

```sh
bash plugins/token-diet/install.sh   # active by default afterwards — restart omp
```

Everything is on after that: ctx-wire PATH shims compress command output
transparently, the codebase-memory-mcp MCP server is **enabled** in `.mcp.json`
(binary + index from the installer), and the skills (`/caveman`, `/yagni`,
`skill://codebase-memory`) are enabled in `~/.omp/agent/config.yml`. Pass
`--no-config` to skip the skills
toggle; `--insecure-tls` / `--ca-file=…` for corporate proxies.
