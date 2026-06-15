---
name: codegraph
description: >-
  Query the codebase's symbol/call graph instead of grep+read. Use for "where is
  X", "who calls X", "what does X call", "impact of changing X", and
  architecture/flow questions — far fewer tokens and tool calls.
---

# CodeGraph — code knowledge graph (MCP)

A local, tree-sitter-built graph of symbols and their relationships (calls,
imports, inherits) stored in SQLite, exposed over MCP. Prefer it over
`grep`/`glob`/`Read` for structural questions: a single call replaces dozens of
grep+read round-trips (~96% fewer tokens on those tasks).

## Prerequisites

- Installed + indexed: `bash plugins/token-diet/install.sh`, or manually
  `codegraph init && codegraph index`.
- `codegraph` MCP server is **enabled by default** in this plugin's `.mcp.json`
  (it just needs the `codegraph` binary on PATH + an index, both from install.sh).
- The server auto-syncs the graph on file changes (file watcher, ~2s debounce).

## Tools

| Tool | Use for |
|---|---|
| `codegraph_search` | locate symbols by name across the repo |
| `codegraph_node` | one symbol's details + source + caller/callee links |
| `codegraph_callers` | every call site of a function |
| `codegraph_callees` | what a function calls |
| `codegraph_explore` | answer an architecture/flow question in one call (related symbols grouped by file + relationships) |
| `codegraph_impact` | what's affected by changing a symbol |
| `codegraph_files` | indexed file structure |
| `codegraph_status` | index health/metrics |

(If only the first few tools appear, the rest are gated behind the
`CODEGRAPH_MCP_TOOLS` env var on the server.)

## When NOT to use it

- Editing/reading a single known file → plain `Read` + `astEdit`.
- Text/prose/config content (not symbols) → `grep` (ctx-wire compresses its output automatically).
- Languages not indexed → falls back to grep; check `codegraph_status`.

Upstream: https://github.com/colbymchenry/codegraph
