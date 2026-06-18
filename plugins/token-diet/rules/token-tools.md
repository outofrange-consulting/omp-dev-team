---
alwaysApply: true
description: Token-saving tool routing (ctx-wire + CodeGraph)
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
- **Code structure via CodeGraph.** When the `codegraph_*` MCP tools are
  available, prefer them over `grep`/`glob`/`Read` for "who calls X", "what does
  X call", "where is symbol Y", "what's the impact of changing Z", and
  architecture questions. A `codegraph_explore`/`codegraph_callers` call usually
  replaces dozens of grep+read round-trips.
- Reserve full-file `Read` for when you actually need to edit or read prose; for
  structure, query the graph first.
