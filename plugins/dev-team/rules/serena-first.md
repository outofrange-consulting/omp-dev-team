---
description: Serena-first protocol — symbolic C# navigation + enforced symbolic C# edits (serena-forge)
globs:
  - "**/*.cs"
  - "**/*.csproj"
  - "**/*.sln"
  - "**/*.slnx"
---

# Serena-first protocol (serena-forge)

Serena provides symbol-level **read and edit** tools for the current repository,
backed by the Roslyn language server. This rule loads whenever C# is in scope.

## Read policy

Native `read` of `.cs` files is allowed, but **prefer Serena** — don't reflexively
dump whole files. A whole-file `read` of a `.cs` file over ~100 lines is nudged
(confirmation / warning) toward the symbolic workflow; bounded reads (with
`limit`/`offset`) and small files pass through. Mandatory workflow for reading C#:

1. `get_symbols_overview` — survey a file's top-level symbols first.
2. `find_symbol` — jump to one symbol's body (`include_body: true` only on the
   symbol you need).
3. `find_referencing_symbols` — the reliable "who calls this" (LSP call sites) —
   use it instead of grep for change-impact analysis.
4. `search_for_pattern` — regex/text fallback for non-symbol matches.

See the `serena-navigate` skill for the full read workflow. (Threshold tunable
via `SERENA_FORGE_READ_MAXLINES`; `0` disables the nudge.)

## Write policy (enforced)

Editing `.cs` via `write` / `edit` / `astEdit` is **BLOCKED globally** by the
`serena-enforce` extension. Change C# through Serena's symbolic edit tools:

- `replace_symbol_body` — replace a method/property/class body.
- `insert_after_symbol` / `insert_before_symbol` — add a new symbol beside one.
- `rename_symbol` — rename a symbol and update every reference via the LSP.
- `safe_delete_symbol` — remove a symbol after a reference check.

See the `serena-refactor` skill for recipes and the CRLF-diff pitfall.

## Build + test gate (blocking)

After Serena C# edits, the `serena-build-net` extension gates the end of the
session: it runs a strict `dotnet build -warnaserror` of the touched project(s)
and then the stack's `dotnet test`. If the build or a test fails, the stop is
**blocked** and the errors are handed back — a red build or failing test is
**unfinished work**; fix it through Serena. A bounded fix counter (default 3)
prevents trapping. Opt out only on request: `SERENA_FORGE_BUILD=0` (whole gate)
or `SERENA_FORGE_TEST=0` (build only).

## No bypass

There is intentionally no escape hatch. If Serena cannot make an edit — the LSP
is unavailable/timed out, the project targets **.NET 9 or lower** (Serena's
Roslyn backend is **.NET 10-only**), or the change can't be expressed
symbolically — **stop and ask the user** to fix Serena or disable the
`serena-enforce` extension. Do **not** work around the block with native edits.

## Onboarding

Serena's tools resolve against the currently activated project. A repo must be
onboarded once (`.serena/` present) before its `.cs` files can be edited — run
the `serena-setup` skill. On a large brownfield solution the first symbolic call
can take ~30 s while Roslyn initializes; that wait is normal — don't conclude a
symbol is missing before it settles.
