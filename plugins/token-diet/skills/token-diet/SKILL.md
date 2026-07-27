---
name: token-diet
description: >-
  How this workspace minimises LLM token spend. Use when the user asks how to
  reduce tokens or cost, what lean-ctx or caveman are, how to set them up, or
  whether OMP already does X natively.
---

# token-diet

Two layers, and a short list of things NOT to rebuild.

## What OMP already does — do not reinvent any of it

- **Compaction.** `compaction.supersedeReads` (default **on**) prunes an older
  read when the same file is read again. `dropUseless` and `pruneToolOutputs`
  trim the rest. Long sessions summarise automatically.
- **Shell output.** `shellMinimizer` ships Rust filters for common tools, on by
  default, plus a hard truncation ceiling.
- **Structural tools.** `ast_grep`, `ast_edit`, `summarizeCode` — search and edit
  without dumping whole files. `read` returns structural summaries by default.
- **Cost and cache visibility.** Native statusline segments: `cost`,
  `cache_read`, `cache_write`, `cache_hit`, `context_pct`, `usage`.
- **Secret redaction.** `secrets.enabled` plus `~/.omp/agent/secrets.yml`.
- **MCP tool schemas.** `tools.xdev` (default on) mounts them as `xd://` devices
  behind a doc budget, so a server costs a mount, not a schema dump.

This plugin used to duplicate the first four. It no longer does.

## Layer 1 — lean-ctx (input tokens)

[lean-ctx](https://github.com/yvgude/lean-ctx) (MIT) is a local Rust binary that
sits between the agent and its tools. `install.sh` installs it and registers
upstream's `pi-lean-ctx` extension, which routes `bash`, `read`, `grep`, `find`
and `ls` through it.

Beyond what OMP does natively, it adds: compression of **file reads, search
results and project context** (not just command output), recognition of 75+ tools
out of the box, and a **persistent session cache** so an unchanged re-read costs
a fraction of a fresh one.

Knobs live in `~/.pi/agent/extensions/pi-lean-ctx/config.json` — that extension
resolves its config against `~/.pi`, not `~/.omp`, so the installer writes it
where the extension actually looks. `mode: replace` swaps the native tools
outright; `additive` (the default here) leaves both available.

**This replaced ctx-wire.** ctx-wire compressed command output only, which meant
hand-maintaining a filter per command — this plugin shipped four of them for
`dotnet` alone. That does not scale, and it is the same duplicate-the-tool
mistake listed above.

## Layer 2 — caveman (output tokens)

`/skill:caveman` makes the agent answer tersely. This is the one axis nothing
else here addresses: OMP and lean-ctx both work on what goes INTO the model.
caveman works on what comes out. It preserves the user's language.

## Measuring

Do not claim a saving you have not measured. `omp usage --history` and `omp stats`
report real token and cost figures; the `cache_hit` statusline segment shows
whether the prompt cache is actually being hit.
