---
alwaysApply: true
description: How this workspace keeps tool output cheap
---

# Token tools

`bash`, `read`, `grep`, `find` and `ls` are routed through **lean-ctx**, which
compresses their output and caches it per session. This is transparent: call the
tools normally. Do not paste raw command output back into the conversation — it
is already summarised, and re-pasting undoes the saving.

- Prefer `read`/`grep`/`find` over shelling out to `cat`/`grep`/`find`. The
  routed tools are compressed and cached; a raw shell equivalent is neither.
- Prefer structural editing (`ast_grep`, `ast_edit`) over reading a whole file to
  change a few lines.
- Need the untruncated output of one command? Ask for it explicitly rather than
  disabling the routing.
