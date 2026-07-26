# ctx-wire filter pack — the four `dotnet` commands OMP does not cover

Four user-tier ctx-wire override filters, merged into
`~/.config/ctx-wire/filters.toml` by `plugins/token-diet/install.sh`:

| filter | what it collapses |
|---|---|
| `dotnet-publish` | strips the restore/build preamble, **keeps** the `-> …/publish/` artifact line and every error/warning (trim/AOT `IL####` and `TrimmerXXXX` warnings must survive) |
| `dotnet-pack` | collapses a clean pack to one line (`Successfully created package` / `Création réussie du package`), keeps errors |
| `dotnet-run` | strips the build preamble, keeps app output, collapses an all-passed MTP test summary |
| `dotnet-tool` | collapses `install`/`update`/`uninstall` success; `list` and failures pass through |

Each filter carries embedded EN+FR tests. `ctx-wire verify` runs them, and so
does the bundled `scripts/verify-filters.py` when ctx-wire isn't installed
(**23/23 pass**).

## Why only these four (and why the others were deleted)

`git-status`, `dotnet-build`, `dotnet-test` and `dotnet-restore` used to ship
here. They are gone because **OMP does them natively, on by default**, in its
own Rust shell minimizer:

- `crates/pi-shell/src/minimizer/filters/git.rs` — `supports()` matches
  `status`, `diff`, `show`, `log`, `add`, `commit`, `push`, `pull`, `branch`,
  `fetch`, `stash`, `worktree`, `merge`, `rebase`, `checkout`, `switch`,
  `restore`, `clean`, `reset`, `tag`.
- `crates/pi-shell/src/minimizer/filters/dotnet.rs` — `supports()` matches
  exactly `build`, `test`, `restore`, `format`.

Running both layers over the same bytes buys nothing and makes two places to
debug when a line goes missing. `publish`, `pack`, `run` and `tool` are **not**
in `dotnet.rs`'s `supports()` list — that is the whole remaining gap.

The `acli` filter went too, with the Atlassian skill: Jira/Confluence now go
through the official remote MCP server, and its token-redaction stage is better
served by OMP's native `secrets.enabled` + a `type: regex` entry in
`~/.omp/agent/secrets.yml`, which applies to **all** outbound text rather than
one CLI's stdout.

## The locale gap (this is the real reason the pack exists)

OMP's non-interactive shell environment pins `LANG=C.UTF-8` / `LC_ALL=C.UTF-8`
**only on Windows**. Verified at
`omp packages/coding-agent/src/exec/non-interactive-env.ts`: `buildNonInteractiveEnv`
returns early for any `platform !== "win32"`, and the `LANG`/`LC_ALL` pair lives
in `WINDOWS_UTF8_ENV_DEFAULT_GROUPS`, which only the win32 branch applies.

Consequence: on **Linux/macOS** a developer's French locale reaches `git` and
`dotnet` unchanged, they emit French, and OMP's English-keyed native filters
silently miss — no error, just full raw output landing in context. That is the
failure this pack was built for, and it is still real.

**The cheapest fix is not more regex — it is pinning the locale.** OMP has no
config key for arbitrary shell env vars (`bash.*` covers `enabled`, `patterns`,
`direnv`, `autoBackground` — nothing else), but the embedded shell seeds itself
from OMP's **own** process environment (`crates/pi-shell/src/shell.rs` iterates
`std::env::vars()` into the shell env), so exporting them before you launch OMP
is enough:

```sh
export DOTNET_CLI_UI_LANGUAGE=en
export LC_MESSAGES=C
omp
```

Per-repo instead of per-machine: put the same two lines in the project's
`.envrc` — `bash.direnv` defaults to `auto`, and the executor folds a repo's
direnv environment into every command.

Either way git and dotnet emit English on every platform, the native filters
apply unchanged, and most of the FR half of this pack becomes redundant. Keep
the FR strings anyway for developers who genuinely want French tooling output.

## Why only git + dotnet were ever localized

We reviewed **all 147 upstream ctx-wire filters**. A localized variant only helps
when the tool itself translates its output *and* the filter keys on that
translated prose. That set is small:

| Tool | Localizes output? | Filter keys on prose? | Localized here |
|---|---|---|---|
| **dotnet publish** | Yes (build + NuGet) | Strips restore/build preamble, keeps the `-> …/publish/` artifact + errors/warnings (no `Build succeeded` line in .NET 10) | ✅ EN+FR |
| **dotnet pack** | Yes (NuGet) | Yes (`Successfully created package` / `Création réussie du package`) | ✅ EN+FR |
| **dotnet run** | Yes (build + app) | Strips build preamble; collapses all-passed MTP test runs | ✅ EN+FR |
| **dotnet tool** | Yes (SDK) | Yes (`was successfully installed/updated`) | ✅ EN+FR |
| git status, dotnet build/test/restore | Yes | Yes — but **OMP's native filters own these now** | ➖ deleted |
| **dotnet format** | Yes | **No** — silent on success; its diagnostics (`error WHITESPACE:`, analyzer IDs) must reach context. Nothing to collapse | n/a |
| **dotnet list package** | keys are English | **No** — `--outdated` / `--vulnerable` tables are the payload you *want* | n/a |
| git log / diff / blame | Yes | **No** — purely structural (blank-strip, truncate, caps) | n/a |
| grep / rg | Diagnostics only | **No** — `group_by` on `file:line:`, structural | n/a |
| npm / pnpm / cargo / go / docker / kubectl / tsc / eslint / pytest / mvn / gradle / … (~140) | **No** — Go/Rust/Node/Python/Java/Ruby/PHP toolchains emit English regardless of `LANG` | — | n/a |

So localizing "all tools" would be almost entirely dead regex: the long tail
emits English in any locale, and the structural filters are already
locale-agnostic by construction.

> **`dotnet build` vs `publish`/`pack` output in .NET 10** — verified against
> SDK 10.0.301: `dotnet build` still prints the classic `Build succeeded.` /
> `0 Error(s)` summary (piped, under a PTY, and with `--tl:off`). `publish` and
> `pack` do **not** — their success markers are the `-> …/publish/` artifact line
> and `Successfully created package` respectively, which is why they need their
> own filters rather than reusing a build one.

## Why no Romanian

The tools worth localizing **ship no Romanian translation**:

- **git** translates to 18 languages (bg, ca, de, el, es, fr, ga, id, is, it,
  ko, pl, pt_PT, ru, sv, tr, uk, vi) — Romanian is not one of them. In a
  `ro_RO` locale `git status` falls back to English.
- The **.NET CLI / MSBuild / VSTest** localize to ~14 languages (cs, de, es, fr,
  it, ja, ko, pl, pt-BR, ru, tr, zh-Hans/Hant) — no Romanian either.

Romanian therefore only ever appears in **user data** (commit messages, file
contents, ticket text) — which must be **preserved**, not filtered. OMP's
mechanical limits (tail window, column cap, artifact spill) handle oversized
data of any language without needing to understand it.

## Microsoft.Testing.Platform (MTP) vs VSTest

`dotnet test` can run on either the classic **VSTest** console (single-line
`Passed! - Failed: 0, …` summary) or the newer **MTP** runner (multi-line
`Test run summary:` block) — and that command is OMP's now. It still matters
here because an MTP test project is a plain console app with an entry point, so
it is *also* run via **`dotnet run`** — which is why the `dotnet-run` filter
collapses an all-passed MTP summary (and preserves failures).

## Updating the French strings

Re-extract from upstream localization when tool versions change:

- MSBuild:  `dotnet/msbuild@main:src/Build/Resources/xlf/Strings.fr.xlf`
- MTP:      `microsoft/testfx@main:src/Platform/Microsoft.Testing.Platform/Resources/xlf/PlatformResources.fr.xlf`
- NuGet:    `NuGet/NuGet.Client@dev:src/NuGet.Core/NuGet.Commands/xlf/Strings.fr.xlf`
- SDK/tool: `dotnet/sdk@main:src/Cli/dotnet/Commands/xlf/CliCommandStrings.fr.xlf`

Then run `ctx-wire verify`, or `python3 scripts/verify-filters.py filters.d`.

## Compressing MCP output

ctx-wire's PATH shims only see **shell commands**, never MCP traffic. For
servers you define yourself, `ctx-wire mcp-wrap install --compress -- <server cmd>`
rewrites that entry to relay through ctx-wire. We deliberately do **not** wrap
anything by default — that would couple the server to a ctx-wire install that may
be absent. For everything else, OMP's own limits apply to MCP results the same as
to shell output.
