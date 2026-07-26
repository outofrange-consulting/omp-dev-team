---
alwaysApply: true
description: Token-saving tool routing (ctx-wire)
---

# Token discipline

- **Command output is filtered before it reaches context.** ctx-wire's PATH
  shims compact noisy command output and scrub secrets transparently — run
  commands normally, **no prefix or wrapper**. Full logs stay on disk, so never
  re-run a command "to see everything" (`ctx-wire gain` shows the savings). If
  ctx-wire isn't installed, nothing changes. Filters are EN+FR for the `dotnet`
  commands OMP's own minimizer doesn't cover; never switch locale to "help" it.
- **This is not a reason to prefer raw shell.** `read`/`grep`/`glob`/`edit`/
  `astEdit` remain the required routing for file reads, searches and edits;
  ctx-wire only compacts `bash` output. (A ctx-wire block auto-injected into
  Claude Code's own user-scope context file says the opposite — correct there,
  since its Read/Grep bypass ctx-wire; wrong here.)
- **Edit symbols structurally, not whole files.** For a known function/class/
  block prefer `astEdit` (with `blockRangeAt`/`summarizeCode` to locate it) over
  read-whole-file → `write`: it touches only that range, avoiding the dominant
  token cost on large files. `write` is for new files or genuine whole-file
  rewrites; `edit` for small anchored textual changes.
