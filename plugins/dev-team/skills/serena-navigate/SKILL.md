---
name: serena-navigate
description: >-
  Read and navigate C# code in the CURRENT repo through Serena's symbolic read
  tools (get_symbols_overview, find_symbol, find_referencing_symbols,
  search_for_pattern) instead of reading whole files. Fetches exact symbol
  bodies, callers, and references on demand. Trigger on "read this class", "find
  the symbol", "who calls X", "navigate the code", or any request to inspect a
  specific type/method, its body, or its callers.
role: worker
user-invocable: true
allowed-tools: read, search, find
---

# serena-navigate — symbolic C# reading

Read C# by **symbol**, not by whole file. Serena's Roslyn-backed language server
lets you pull a class outline, a single method body, or every caller of a symbol
without loading an entire `.cs` file into context. This keeps context lean and
answers precise.

This skill covers **reading and navigation only**. It does not edit code — that
is `serena-refactor`.

## The read workflow

Do NOT open a `.cs` file with the native `read` tool by reflex. Instead:

1. **Outline first.** Call `get_symbols_overview` on the target file to get its
   top-level symbols (namespaces, classes, methods, signatures) — a cheap map of
   the file without its full contents.
2. **Fetch one body.** Call `find_symbol` with the symbol's name/path to pull
   just that symbol's source. Request children (e.g. a class's methods) only when
   you need them. This replaces reading the whole file.
3. **Find callers.** Call `find_referencing_symbols` on a symbol to list every
   place that references it — the reliable "who calls this" answer, resolved by
   the LSP rather than by grep guessing.
4. **Regex fallback.** Call `search_for_pattern` when you need a textual/regex
   match (a string literal, an attribute, a TODO) that isn't a named symbol
   lookup.

### Verified Serena read tools

Use only these names:

- `get_symbols_overview` — top-level symbol outline of a file (start here).
- `find_symbol` — fetch a symbol (class/method/property) body by name or path;
  can include children and depth.
- `find_referencing_symbols` — all references/callers of a symbol ("who calls").
- `find_declaration` — jump to where a symbol is declared.
- `find_implementations` — implementations of an interface or abstract member.
- `search_for_pattern` — regex/text search across the repo.
- `list_dir` — list a directory within the project.
- `find_file` — locate a file by name/pattern.
- `read_file` — read a file (or line range) when a full read is genuinely needed;
  prefer the symbol tools above.
- `get_diagnostics_for_file` / `get_diagnostics_for_symbol` — compiler
  diagnostics for a file or a specific symbol.

## Typical requests

- **"Read this class `OrderService`"** → `find_symbol` on `OrderService`
  (with children if you need the methods), not a whole-file read. Preview with
  `get_symbols_overview` first if you're unsure of the file's shape.
- **"Find the symbol `TenantResolver`"** → `find_symbol` by name; if ambiguous,
  `get_symbols_overview` on the candidate file, or `find_declaration`.
- **"Who calls `InvokeWithRequestContextAsync`"** →
  `find_referencing_symbols` on that method.
- **"Navigate the code" / "what's in this file"** → `get_symbols_overview`, then
  `find_symbol` on whatever the user drills into.
- **"Where is this string / attribute used"** → `search_for_pattern` with the
  regex.

## Notes and prerequisites

- **This repo only.** Serena's tools resolve against the currently activated
  project. If the project isn't active, run the `serena-setup` skill.
- **.NET 10 only.** The Roslyn backend requires .NET 10+; on .NET 9 projects the
  language server times out. If symbol lookups fail on a .NET 9 solution, stop
  and tell the user rather than fighting the LSP.
- **First-use warm-up.** On a large brownfield solution the language server may
  take up to ~30s to finish initializing before symbol results are reliable. If a
  lookup returns nothing immediately after activation, retry once after it
  settles rather than concluding the symbol is absent.
- **Reading `.cs` is still allowed — but whole-file reads are nudged.**
  serena-forge blocks *writes* to `.cs`, not reads. However, a native whole-file
  `read` of a `.cs` file over ~100 lines triggers a confirmation nudge (the
  `serena-enforce` read guard) steering you to `get_symbols_overview` →
  `find_symbol` (`include_body: true`) on just the target. A bounded `read` (with
  `limit`/`offset`) and files under the threshold pass through. Reach for the
  symbol tools first so you pull the minimum needed; the threshold is tunable via
  `SERENA_FORGE_READ_MAXLINES` (0 disables it).
