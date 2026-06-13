---
alwaysApply: true
description: Token-saving tool routing (RTK + CodeGraph)
---

# Token discipline

- **Shell output via RTK.** If `rtk` is installed, run noisy inspection commands
  through it: `rtk git status`, `rtk grep ...`, `rtk find ...`, `rtk cargo test`,
  `rtk npm test`, `rtk ls -R`, etc. It compresses output 60–90% before it hits
  context. If you get `rtk: command not found`, run the command normally and
  carry on (don't loop).
- **Code structure via CodeGraph.** When the `codegraph_*` MCP tools are
  available, prefer them over `grep`/`glob`/`Read` for "who calls X", "what does
  X call", "where is symbol Y", "what's the impact of changing Z", and
  architecture questions. A `codegraph_explore`/`codegraph_callers` call usually
  replaces dozens of grep+read round-trips.
- Reserve full-file `Read` for when you actually need to edit or read prose; for
  structure, query the graph first.
