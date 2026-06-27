---
name: codebase-memory
description: >-
  Query the codebase's persistent knowledge graph instead of grep+read. Use for
  "where is X", "who calls X", "what does X call", "impact of changing X", and
  architecture/flow questions — far fewer tokens and tool calls. For precise C#
  semantic operations (rename, exact references, diagnostics, hover), use the
  csharp-ls LSP instead.
---

# codebase-memory-mcp — code knowledge graph (MCP)

A local, tree-sitter-built knowledge graph of symbols and their relationships
(calls, imports, inherits, HTTP routes, cross-service links) persisted on disk and
exposed over MCP. Type resolution is sharpened by an embedded **Hybrid LSP** (C#,
Python, TS/JS/JSX/TSX, PHP, Go, C, C++, Java, Kotlin, Rust). Prefer it over
`grep`/`glob`/`Read` for structural questions: a single call replaces dozens of
grep+read round-trips (~99% fewer tokens on those tasks), 158 languages.

## Prerequisites

- Installed + indexed: `bash plugins/token-diet/install.sh`, or manually
  `codebase-memory-mcp cli index_repository '{"repo_path": "/abs/path"}'`.
- `codebase-memory-mcp` MCP server is **enabled by default** in this plugin's
  `.mcp.json` (it just needs the `codebase-memory-mcp` binary on PATH + an index,
  both from install.sh).
- The server auto-syncs the graph on file changes after the first index.

## Tools

| Tool | Use for |
|---|---|
| `search_graph` | locate symbols by label / name pattern / file / degree |
| `search_code` | grep-like text search within indexed project files |
| `get_code_snippet` | one symbol's source by qualified name |
| `trace_path` | callers and callees (BFS); alias `trace_call_path` |
| `get_architecture` | codebase overview: languages, packages, routes, hotspots, clusters — answers a flow/architecture question in one call |
| `query_graph` | Cypher-like read-only graph queries |
| `detect_changes` | map a git diff to affected symbols + blast-radius / risk |
| `get_graph_schema` | node/edge counts, relationship patterns, properties |
| `index_repository` | (re)index a repo; auto-sync keeps it fresh afterward |
| `index_status` | indexing status |
| `list_projects` / `delete_project` | indexed projects + node/edge counts; remove |
| `manage_adr` | CRUD for Architecture Decision Records |
| `ingest_traces` | ingest runtime traces to validate HTTP_CALLS edges |

## Mapping from the old CodeGraph tools

`codegraph_search` → `search_graph` / `search_code`; `codegraph_node` →
`get_code_snippet`; `codegraph_callers`/`codegraph_callees` → `trace_path`;
`codegraph_explore` → `get_architecture` / `query_graph`; `codegraph_impact` →
`detect_changes`; `codegraph_files` → `get_architecture` / `list_projects`;
`codegraph_status` → `index_status`.

## When NOT to use it

- Editing/reading a single known file → plain `Read` + `astEdit`.
- Text/prose/config content (not symbols) → `grep` (ctx-wire compresses its output automatically).
- Languages not indexed → falls back to grep; check `index_status`.
- **Precise C# semantic operations the graph can't give you** — exact
  find-all-references, rename, live diagnostics/type errors, hover/signature
  help, completion → use the **csharp-ls LSP** (wired into OMP via `lsp.json`,
  auto-activated on `.sln`/`.slnx`/`.csproj`). The embedded Hybrid LSP only
  resolves types well enough to build the graph; it is **not** a full language
  server. Rule of thumb: structural/whole-repo questions → codebase-memory-mcp;
  point-precise editor-grade C# semantics → csharp-ls.

Upstream: https://github.com/DeusData/codebase-memory-mcp
