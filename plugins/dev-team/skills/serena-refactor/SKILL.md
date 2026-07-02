---
name: serena-refactor
description: >-
  Edit and refactor C# symbols through Serena's LSP-backed symbolic write tools
  instead of raw text edits. Use for renaming a symbol, moving a class, replacing
  or inserting a method, or any structural change to a .cs file — because
  write/edit/astEdit on .cs are blocked plugin-wide and must be redirected to
  Serena. Also use whenever a native write/edit on a .cs file was just denied.
role: worker
user-invocable: true
allowed-tools: read, bash(git diff*), bash(git status*)
---

# serena-refactor — symbolic C# editing

Native `write`, `edit`, and `astEdit` on `.cs` files are **denied globally** by
dev-team's `serena-enforce` extension (write-only enforcement, active in every
repo). All C# code changes go through **Serena's symbolic write tools**, which
edit by *symbol* (class / method / property) via the Roslyn LSP rather than by
line-matching text. This keeps edits surgical and keeps Serena's index
consistent.

## Workflow: locate → edit → verify

1. **Locate the symbol** (Serena read tools — see the `serena-navigate` skill):
   - `get_symbols_overview` on the file to see its top-level symbols.
   - `find_symbol` with the name path (e.g. `MyClass/DoWork`) to get the exact
     symbol; pass `include_body: true` when you need to read it before editing.
   - `find_referencing_symbols` before any rename/move/delete, so you know what
     depends on it.
2. **Edit** with the matching write tool (below).
3. **Verify** with `get_diagnostics_for_symbol` (or `get_diagnostics_for_file`)
   to confirm the edit compiles with no new errors — then **check the git diff**
   (see the CRLF pitfall — not optional when `.editorconfig` enforces CRLF).

> **Build + test gate (automatic, blocking).** The `serena-build-net` extension
> queues the touched `.csproj` on every Serena symbolic edit and, at
> `session_stop` (when you're about to finish), runs a strict scoped
> `dotnet build -warnaserror` of each touched project and then the stack's
> `dotnet test`. If the build fails **or** a test fails, the stop is **BLOCKED**
> (OMP `session_stop` hook) and the errors are handed back — **fix them through
> Serena before finishing; a red build or failing test is unfinished work.**
> `get_diagnostics_*` is your fast in-loop check; the stop-time build+test is the
> real gate. A bounded fix counter (`maxFixes`, default 3, from
> `.omp/dev-team.json → implVerify`) degrades to a warning once spent, so you're
> never trapped. Opt out only if the user asks: `SERENA_FORGE_BUILD=0` (whole
> gate) or `SERENA_FORGE_TEST=0` (build-only, skip tests).

## Verified Serena write tools

Use only these (confirmed present). Do **not** invent tool names.

| Tool | Use for |
|------|---------|
| `replace_symbol_body` | Replace the full body of one method/property/class you already located. The primary "edit this method" tool. |
| `insert_after_symbol` | Add a new symbol (method, property, nested type) immediately after an existing one. |
| `insert_before_symbol` | Add a new symbol immediately before an existing one. |
| `rename_symbol` | Rename a symbol **and update every reference** via the LSP. The correct answer to "rename this symbol" — never hand-edit call sites. |
| `safe_delete_symbol` | Remove a symbol after checking references. Use for "delete this method/class". |

Fine-grained fallbacks also exist (`replace_lines`, `insert_at_line`,
`delete_lines`, `replace_content`, `replace_in_files`, `create_text_file`).
Prefer the symbol-level tools above; reach for line/content tools only when the
change isn't a whole symbol (e.g. editing a `using` block).

### Recipes

**Edit a method body** — `find_symbol` (`include_body: true`) to read it, then
`replace_symbol_body` with the new body.

**Add a method to a class** — `insert_after_symbol` (or `insert_before_symbol`)
targeting a sibling method, passing the new method text.

**Rename a symbol** — `rename_symbol` on the definition. It rewrites references
across the project through the LSP. Afterwards run `get_diagnostics_for_file` on
the most-affected files.

**Move a class** — Serena has **no single "move" tool**. Compose it:
1. `find_symbol` (`include_body: true`) on the class to capture its full text.
2. Create/populate the destination: `create_text_file` for a new file, or
   `insert_after_symbol` to drop it into an existing file. Add the correct
   `namespace` / `using` directives for the new location.
3. `safe_delete_symbol` to remove it from the origin file.
4. `find_referencing_symbols` (run in step 1, before deleting) tells you which
   files need `using`/namespace fixups.
5. `get_diagnostics_for_file` on origin, destination, and referencing files to
   confirm the move compiles.

## CRITICAL pitfall — a format hook can rewrite your .cs at turn end (CRLF churn)

If a `dotnet format` hook runs over edited `.cs` files in your environment, it
can amplify a one-line symbolic edit into a whole-file CRLF/whitespace diff —
the single most common way a clean Serena refactor turns into an unreviewable
diff when `.editorconfig` **forces CRLF** but some source files — notably several
`Program.cs` — are checked in as **LF**. `dotnet format` normalizes line endings
for the whole file, bundling your surgical change with a CRLF rewrite of every
line.

**Always do this after a Serena edit to a .cs file:**

1. **Check the diff.**
   ```bash
   git diff --stat
   git diff -- path/to/File.cs
   ```
   If the only real change is your symbol but the diff shows the whole file
   changed (or `git diff --stat` shows a suspiciously large line count), the
   format step rewrote line endings.

2. **If the diff is polluted, escape via `--no-verify` + `perl -i` reinsert:**
   ```bash
   git commit --no-verify -m "refactor(scope): <ticket> <description>"
   perl -i -pe 's/\r$//' path/to/Program.cs   # strip CR the formatter added
   ```
   (`--no-verify` also sidesteps offline husky pre-commit/pre-push hooks that
   fail with no network. Do **not** add npm/husky dependencies to work around
   them.) Re-inspect `git diff` until only your symbol change remains, then
   amend/commit.

3. **Prefer to avoid the churn entirely** when the file is LF-on-disk: keep edits
   symbol-scoped, and after the turn's format flush, verify line endings match
   what's committed before you stage.

## When Serena cannot make the edit

If Serena can't perform the change — the Roslyn LSP hasn't finished initializing
(large brownfield solutions take up to ~30s for `projectInitializationComplete`),
it timed out, the repo is `.NET 9` (Serena's Roslyn backend reliably trips a 10s
BuildHost timeout — serena-forge is `.NET 10`-only), or the symbolic tools
genuinely can't express the change — **do not attempt to work around the write
block.** There is no bypass.

1. If it looks like a warm-up delay, wait for the LSP to finish initializing and
   retry the symbolic edit once.
2. Otherwise, **stop and tell the user** exactly what failed (LSP unavailable /
   timed out / .NET 9 / change not expressible symbolically) and ask them to fix
   Serena or disable the `serena-enforce` extension. Do not fall back to native
   `write`/`edit` — the block is intentional.
