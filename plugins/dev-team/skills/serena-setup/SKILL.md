---
name: serena-setup
description: >-
  Onboard the CURRENT repository with Serena so its Roslyn-backed symbolic
  read/edit tools work. Activates the project, sets ignored_paths, pre-indexes,
  runs Serena onboarding, verifies the C# language server, and wires .gitignore
  so memories are committed. Trigger on "onboard serena", "set up serena here",
  "index this repo with serena", "activate serena", "serena isn't working / can't
  find symbols / is stalling", or when a Serena symbolic tool errors or returns
  nothing on a repo that was never onboarded.
role: worker
user-invocable: true
allowed-tools: read, bash, write, search, find
---

# Serena setup — onboard the current repo

Serena gives symbol-level **read and edit** tools (find/rename/replace a symbol,
find references) for the repo you are in right now. dev-team's **serena-forge**
integration enforces this globally: direct `write`/`edit`/`astEdit` on `.cs`
files is DENIED (by the `serena-enforce` extension) and you are redirected to
Serena's symbolic edits. So a repo you actually want to change in C# must be
onboarded first, or you cannot edit its `.cs` files at all.

This skill onboards **one repo** — the current working directory.

## STOP — the .NET 10-only rule (read this first)

Serena's C# backend is the Roslyn **Microsoft.CodeAnalysis.LanguageServer**,
which **requires .NET 10 or newer**.

> **WARNING — do NOT onboard a .NET 9 (or older) project.**
> On .NET 9 Roslyn's `BuildHostProcessManager` throws a
> `System.TimeoutException` (hardcoded ~10s BuildHost connect timeout — Serena
> issue #513). Onboarding will appear to hang for ~10s and then fail, and every
> subsequent symbolic call fails the same way. **The C# LSP will not come up. Do
> not force it.**

The SDK version does not matter; the **project's target framework** does. Check
it before onboarding:

```bash
# Any project targeting net9.0 or lower => DO NOT onboard.
grep -rEn '<TargetFrameworks?>' --include='*.csproj' . 2>/dev/null
[ -f global.json ] && cat global.json
```

If **any** `.cs` project you need to touch targets `net9.0`, `net8.0`, or lower,
STOP and tell the user: this repo cannot be onboarded with Serena's Roslyn
backend, and ask them how to proceed (fix Serena's requirements or disable the
`serena-enforce` extension for this repo). (`net10.0` and mixed solutions where
the projects you edit are all `net10.0+` are fine.)

## Onboarding steps

The Serena MCP server is provided by the dev-team plugin (`.mcp.json`) and starts
automatically — drive it through the MCP tools below. (For reference the server
launches as
`uvx -p 3.13 --from git+https://github.com/oraios/serena serena start-mcp-server --context ide-assistant`,
with no `--project`; the project is bound at runtime via `activate_project`. The
`ide-assistant` context is the one meant for coding agents like OMP that bring
their own read/edit/shell tools and want only Serena's semantic layer.)

1. **Confirm the framework** with the grep above. If it is not `net10.0+`, STOP
   (see the .NET 10-only rule).

2. **Activate the current repo.** Call `activate_project` with the **absolute**
   path to the repo root (use `pwd` — always absolute, never relative). This
   registers the project and creates `.serena/project.yml`.

3. **Set `ignored_paths` before indexing.** Exclude build output and generated
   code so the index is smaller/faster and `find_symbol` never surfaces
   generated noise. Add these to `.serena/project.yml` (create the
   `ignored_paths:` block if absent):

   ```yaml
   # .serena/project.yml
   ignored_paths:
     - "**/bin/**"
     - "**/obj/**"
     - "**/*.g.cs"           # generated
     - "**/*.Designer.cs"    # designer-generated
     - "**/*.AssemblyInfo.cs"
     - "**/node_modules/**"  # if the repo has any JS tooling
   ```

4. **Pre-index the repo** (avoid the first-`find_symbol` cold start). Build the
   symbol index up front so the first symbolic call in a real session doesn't pay
   Roslyn's cold start:

   ```bash
   uvx -p 3.13 --from git+https://github.com/oraios/serena \
     serena project index "$(pwd)"
   ```

   On a large brownfield solution this can take a while (it downloads the Roslyn
   language server from NuGet on first use and walks the whole tree) — that is the
   cost you pay *now* instead of on the user's first query. If it errors on a
   `.NET 9` target, that's the same .NET 10-only issue (step 1) — do not force it.

5. **Run onboarding.** Call `onboarding`. This inspects the project and writes
   Serena's initial project memories (structure, build/test commands,
   conventions) into `.serena/memories/`. Confirm with `list_memories`; read
   Serena's own guidance with `initial_instructions`. These memories are meant to
   be **committed** — they are the persistence layer that lets later sessions skip
   re-exploration (see "Repo housekeeping" below).

6. **Wait for the first index (~30s) — do not retry.** Roslyn indexes the whole
   solution and emits `workspace/projectInitializationComplete` when done; Serena
   waits up to **~30 seconds**. On a large brownfield solution the first symbolic
   call can sit near that limit while the Roslyn LS package downloads and indexes.
   **This wait is normal — do not hammer retries, and do not conclude Serena is
   broken before ~30s have elapsed.**

7. **Verify the C# LSP came up.** Smoke-test with a cheap symbolic read — call
   `get_symbols_overview` on one real `.cs` file. A list of symbols means Roslyn
   is live and you may use all Serena read/edit tools. Alternatives: `find_symbol`
   for a known class, or `get_diagnostics_for_file`.
   - A `System.TimeoutException` here almost always means either (a) a non-`net10.0`
     project slipped in — recheck step 1, or (b) the ~30s init hasn't finished —
     wait once more, then smoke-test again.
   - If it keeps timing out on a confirmed `net10.0` repo, treat the LSP as
     unavailable and **stop and tell the user** (fix Serena or disable the
     `serena-enforce` extension) rather than looping or working around it.

8. **Wire `.gitignore` so memories are committed.** Ensure the repo ignores only
   Serena's churny cache and keeps `project.yml` + `memories/` tracked. Append
   this block if it isn't present (do not clobber an existing `.gitignore` — only
   add missing lines):

   ```gitignore
   # Serena local state — ignore ONLY the machine-local index cache.
   # Keep .serena/project.yml and .serena/memories/ tracked (committed memories =
   # the persistence layer; later sessions read them instead of re-exploring).
   .serena/cache/
   ```

   Then `git add .serena/project.yml .serena/memories/` so the onboarding output
   is captured for the team. (Skip committing memories only if the user says
   their memories may contain repo-sensitive detail they don't want in git.)

9. **Confirm state** any time with `get_current_config` (active project + config).

## Onboarding on demand (repo not yet initialized)

serena-forge is global, so you will land in repos that were never onboarded.
Because `.cs` writes are blocked everywhere, an un-onboarded repo cannot be
edited until this skill runs. When C# work is requested in such a repo (no
`.serena/` folder), **propose onboarding to the user and run this skill once they
agree** — the session onboarding hint and the write-block message both steer you
here. Do not silently skip onboarding, and never fall back to a native `.cs` edit
to route around the block.

## What `.serena/` contains

- **`project.yml`** — per-project Serena config (language `csharp`,
  `ignored_paths`, etc.).
- **`project.local.yml`** — optional local overrides (not committed).
- **`memories/`** — project memories written by `onboarding` / `write_memory`
  (managed with `read_memory`, `edit_memory`, `rename_memory`, `delete_memory`).
- **`cache/`** — machine-local language-server caches (ignored).

Global Serena config lives separately at `~/.serena/serena_config.yml`. To
un-onboard a repo, call `remove_project`; deleting `.serena/` also resets it.

## When onboarding can't succeed

Because `.cs` writes are blocked globally, a repo where Serena's LSP won't come
up leaves you unable to edit its `.cs` files. There is **no bypass**.

- If it's the normal ~30s first-index wait, let it finish and retry.
- If onboarding genuinely fails (`.NET 9`, the LSP never comes up, a download
  error), **stop and tell the user** what failed and ask them to fix Serena or
  disable the `serena-enforce` extension. Report the specific cause; don't loop
  or fall back to native edits.

## Pitfall — Serena `.cs` edits get reformatted at end of turn (CRLF churn)

Not a setup step, but flag it while onboarding a .NET repo: if a `dotnet format`
hook runs over edited `.cs` files in your environment, it can amplify a surgical
Serena symbolic edit into a whole-file CRLF/whitespace diff — this happens when
`.editorconfig` enforces CRLF while some sources (e.g. `Program.cs`) are checked
in as LF, and `dotnet format` normalizes line endings for the whole file. Handled
by the **serena-refactor** skill (check the diff; commit `--no-verify` and
re-insert via `perl -i` if polluted) — mention it, but don't disable the
formatter here.
