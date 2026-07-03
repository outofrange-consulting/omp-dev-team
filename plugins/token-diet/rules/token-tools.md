---
alwaysApply: true
description: Token-saving tool routing (ctx-wire)
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
- **This does not override OMP's own tool policy.** `read`/`grep`/`glob`/`edit`/
  `astEdit` are still the required routing for file reads, searches, and edits —
  ctx-wire only compresses `bash` tool output; it is not a reason to prefer raw
  shell over those built-ins. (A Claude-Code-oriented ctx-wire block — e.g. one
  `ctx-wire init claude` auto-injects into `~/.claude/CLAUDE.md` — says the
  opposite; that's because Claude Code's own Read/Grep bypass ctx-wire, so
  shelling out is its only route to compression. OMP's built-ins are already
  token-optimized, so that advice does not apply here.)
- **If compression/shims seem inactive** (raw uncompressed command output, or
  `command -v ctx-wire` failing) the shim install most likely ran after this
  OMP session started — PATH updates from `~/.local/bin` never reach an
  already-running process. Say so and ask for an OMP restart; don't fall back
  to a manual `rtk`/`ctx-wire` prefix, and don't conclude the tool is missing.
- Reserve full-file `Read` for when you actually need to edit or read prose;
  for structure, prefer symbol-scoped tools over dumping whole files.
- **Edit symbols structurally, not whole files.** To change a known function /
  class / block, prefer the native AST editor (`astEdit`, and `blockRangeAt` /
  `summarizeCode` to locate it) over `Read` the whole file → `write` it back. A
  targeted `astEdit` touches only the symbol's range — it avoids re-reading and
  re-emitting the entire file (the dominant token cost on large files) and is
  less merge-error-prone. Full-file `write` is for new files or genuine
  whole-file rewrites; `edit` (anchored) for small textual changes; `astEdit`
  for structural changes to existing code. (OMP's native AST tools cover the
  edit side.)
- **Re-reads are deduped.** Reading the same unchanged file again returns a short
  stub, not the bytes — the earlier read is still in context, so reuse it instead
  of re-reading to "refresh". (Editing the file, or compaction, lets a real
  re-read through.) Likewise, don't paste/echo the same large output twice:
  byte-identical repeated blocks are collapsed before each model call.
