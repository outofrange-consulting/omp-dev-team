---
alwaysApply: true
description: Token-saving tool routing (ctx-wire + codebase-memory-mcp)
---

# Token discipline

- **Command output is auto-compressed.** ctx-wire transparently filters noisy
  command output (build/test/lint/git/search) and scrubs secrets *before* it
  reaches context — just run commands normally, **no prefix or wrapper**. Full
  logs are kept on disk; don't re-run a command to "see everything". (`ctx-wire
  gain` shows the savings.) If ctx-wire isn't installed, nothing changes.
  Compaction is **locale-aware** for git/dotnet (EN+FR filters), and the
  **context-mode** plugin sandboxes any-language output (incl. Romanian) — so
  non-English command output is compacted too; never switch locale to "help" it.
- **Code structure via codebase-memory-mcp.** When the codebase-memory-mcp tools
  are available, prefer them over `grep`/`glob`/`Read` for "who calls X", "what
  does X call", "where is symbol Y", "what's the impact of changing Z", and
  architecture questions. A `get_architecture`/`trace_path` call usually replaces
  dozens of grep+read round-trips; `detect_changes` gives the blast radius of a
  diff; `search_graph`/`get_code_snippet` locate and fetch a symbol.
- **Precise C# semantics → csharp-ls LSP, not the graph.** For editor-grade C#
  operations the knowledge graph can't answer — exact find-all-references,
  rename, live diagnostics/type errors, hover/signature help, completion — use
  the `csharp-ls` LSP (wired via OMP's native LSP integration, auto-activated on
  `.sln`/`.slnx`/`.csproj`). codebase-memory-mcp's embedded Hybrid LSP only
  resolves types well enough to build the graph; it is not a full language
  server. Structural/whole-repo questions → codebase-memory-mcp; point-precise C#
  semantics → csharp-ls.
- Reserve full-file `Read` for when you actually need to edit or read prose; for
  structure, query the graph first.
- **Edit symbols structurally, not whole files.** To change a known function /
  class / block, prefer the native AST editor (`astEdit`, and `blockRangeAt` /
  `summarizeCode` to locate it) over `Read` the whole file → `write` it back. A
  targeted `astEdit` touches only the symbol's range — it avoids re-reading and
  re-emitting the entire file (the dominant token cost on large files) and is
  less merge-error-prone. Full-file `write` is for new files or genuine
  whole-file rewrites; `edit` (anchored) for small textual changes; `astEdit`
  for structural changes to existing code. (We do **not** route edits through a
  symbol-server MCP — codebase-memory-mcp is read-only and OMP's native AST tools
  cover the edit side.)
- **Re-reads are deduped.** Reading the same unchanged file again returns a short
  stub, not the bytes — the earlier read is still in context, so reuse it instead
  of re-reading to "refresh". (Editing the file, or compaction, lets a real
  re-read through.) Likewise, don't paste/echo the same large output twice:
  byte-identical repeated blocks are collapsed before each model call.
