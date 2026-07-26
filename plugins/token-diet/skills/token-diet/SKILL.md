---
name: token-diet
description: >-
  What this workspace still does to cut LLM token spend, and what OMP already
  does natively. Use when the user asks how to reduce tokens/cost, what ctx-wire
  or caveman are, or whether OMP already covers X.
---

# token-diet — what is left after OMP 17.x

This plugin used to be a runtime layer: it deduped reads, collapsed repeated
blocks, metered the prompt cache, and hid tool schemas. **OMP absorbed all of
that.** What remains is the narrow set of things the harness does not do.

## What OMP already does — do not reinvent it

| Native | Default | What it covers |
|---|---|---|
| `compaction.supersedeReads` | **on** | Re-reading a file prunes the OLDER result (`[Superseded by a newer read of this file]`), cache-aware, every turn. Note the direction: the **newest** bytes are the ones kept. |
| `compaction.dropUseless` | **on** | Elides tool results flagged contextually useless (no matches, timed-out waits) once consumed. |
| `pruneToolOutputs` | built in | Age-based blanking of old tool results to `[Output truncated - N tokens]`. |
| `shellMinimizer` (Rust filters) | **on** | Per-command output filters, incl. `git` (status/diff/log/…) and `dotnet build\|test\|restore\|format`. |
| bash output limits | built in | 50 KB tail window, per-line column cap, and artifact spill — the full payload stays at `artifact://<id>`. |
| `secrets.enabled` + `secrets.yml` | off (turn it on) | Obfuscates matched secrets on **every** outbound message — including ones that arrived via `read .env` or an MCP result, which no command-output filter can see. |
| statusline `cost` / `cache_read` / `cache_write` / `cache_hit` / `context_pct` / `usage` | segments | Live cost and prompt-cache health. No plugin, no meter, no `/cache-health`. |
| `tools.xdev` | **on** | Rarely-used and MCP tools mount as `xd://` devices instead of shipping their schemas every request. Nothing to configure. |
| `astGrep` / `astEdit` / `summarizeCode` / `blockRangeAt` | built in | Structural search and edit without dumping whole files. |
| `/compact`, `/handoff`, auto-compaction | built in | History summarization. |

Corollary: **do not build a plugin-side context transform.** Anything that
rewrites *old* messages mutates the prefix the provider KV-caches, and cached
input is ~10x cheaper than fresh input — a cache bust costs more than the bytes
it saves.

## What is genuinely left (and is what this plugin ships)

1. **Semantic command-output filters.** OMP truncates *mechanically*: a tail
   window and a column cap. It does not know that a 20 KB all-green
   `dotnet publish` collapses to one artifact-path line. ctx-wire filters do,
   and they know it **in French too**. We ship only the four `dotnet`
   subcommands OMP's own `dotnet` filter does not claim — `publish`, `pack`,
   `run`, `tool` — because duplicating `build`/`test`/`restore` would be two
   passes over the same bytes. See `plugins/token-diet/ctx-wire/README.md`,
   including the **locale trap**: OMP's `LANG=C.UTF-8` hardening is
   Windows-only, so on Linux/macOS a French locale reaches git/dotnet and the
   native English filters silently miss.
2. **Output brevity.** Everything above shrinks *input*. Nothing in OMP (or in
   upstream agentic-dev-team) targets the tokens the model *writes*. That is
   `/caveman` — `skill://caveman`.

## Decision guide

- Running shell commands? Just run them. Output is filtered and secret-scrubbed
  on the way in; `ctx-wire gain` shows the savings.
- Reading or editing a known file? `read` + `astEdit`. Not `cat`/`sed` via bash.
- Want terser replies to cut **output** tokens? `/caveman` (`skill://caveman`).
- Want to see live cost / cache health? Native statusline segments:
  `statusLine.preset: custom` with
  `rightSegments: [cost, cache_hit, cache_write, context_pct, usage]`.
- Worried about secrets reaching the provider? `secrets.enabled: true` plus
  regex entries in `~/.omp/agent/secrets.yml`. Not a command-output filter.
- Long, prose-heavy session and you have **measured** a healthy cache-read
  ratio? Then, and only then, `TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full` opts
  into the compressor. It is off by default on purpose.

## Setup (once per machine)

```sh
bash plugins/token-diet/install.sh   # then restart omp
```

Installs ctx-wire + its PATH shims, merges the four filters, mirrors the
extensions and this rule into `~/.omp/agent`, and merges `config.snippet.yml`.
`--no-config` skips the config merge; `--insecure-tls` / `--ca-file=…` are for
corporate TLS-intercepting proxies.
