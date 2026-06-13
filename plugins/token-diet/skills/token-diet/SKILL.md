---
name: token-diet
description: >-
  How this workspace minimizes LLM token spend. Use when the user asks how to
  reduce tokens/cost, what RTK / CodeGraph / caveman are, how to set them up, or
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
| **RTK** (Rust Token Killer) | command **output** is dumped raw into context | 60–90% smaller `git/grep/find/test` output |
| **CodeGraph** (MCP) | no persistent cross-file **symbol/call graph** | ~96% fewer tokens for "who calls X / impact / architecture" vs grep+read |
| **caveman** (skill) | agent **output** is verbose prose | ~65% fewer output tokens, on demand |

## Decision guide

- Running shell commands? → they auto-route through `rtk` (see the always-on
  rule) when it's installed.
- "Where is X / who calls X / what breaks if I change X / how does this module
  fit together?" → use `skill://codegraph` (the `codegraph_*` MCP tools).
- Editing one known file / reading docs/prose → plain `Read` + `astEdit`.
- Want terse, fragment-style replies to save output tokens → `/caveman`
  (`skill://caveman`).

## Setup (once per machine / project)

```sh
bash plugins/token-diet/install.sh
```

Then enable the CodeGraph MCP server (it ships `enabled: false`): set
`enabled: true` for `codegraph` in your merged `.mcp.json`, after the project is
indexed (`codegraph init && codegraph index`).
