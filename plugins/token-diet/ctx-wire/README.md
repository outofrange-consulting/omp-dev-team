# ctx-wire multilingual filter pack

ctx-wire's bundled filters key on **English** tool output. When a developer runs
in a French locale (`LANG`/`LC_MESSAGES=fr_*`, `DOTNET_CLI_UI_LANGUAGE=fr`), the
English regexes stop matching and noisy raw output reaches context. This pack
ships **EN + FR** override filters (`filters.d/`) that token-diet's `install.sh`
merges into `~/.config/ctx-wire/filters.toml` (user tier — overrides built-ins).

The FR strings are taken **verbatim from each tool's own localization** (git
`po/fr.po`, MSBuild `Strings.fr.xlf`, VSTest `Resources.fr.xlf`), not guessed.
Every filter carries inline EN+FR tests; `ctx-wire verify` runs them.

## Why only git + dotnet (the "all tools" review)

We reviewed **all 147 upstream filters**. A localized variant only helps when the
**tool itself translates its output** *and* the filter keys on that translated
prose. That set is small:

| Tool | Localizes output? | Filter keys on prose? | Localized here |
|---|---|---|---|
| **git status** | Yes (gettext) | Yes (`On branch`, hints, `nothing added…`) | ✅ EN+FR |
| **dotnet build** | Yes (satellite asm) | Yes (`Build succeeded`, `0 Warning(s)`) | ✅ EN+FR |
| **dotnet test** | Yes (satellite asm) | Yes — VSTest (`Passed!`, `Failed:`) **and** MTP (`Test run summary:` block) | ✅ EN+FR |
| **dotnet restore** | Yes (NuGet) | Yes (`All projects are up-to-date`, `Restored …`, `NU####`) | ✅ EN+FR |
| **dotnet run** | Yes (build + app) | Strips build preamble; collapses all-passed MTP test runs | ✅ EN+FR |
| **dotnet tool** | Yes (SDK) | Yes (`was successfully installed/updated`) | ✅ EN+FR |
| git log / diff / blame / list | Yes | **No** — purely structural (blank-strip, truncate, caps) | n/a |
| grep / rg | Diagnostics only | **No** — `group_by` on `file:line:`, structural | n/a |
| jira (CLI) | No (Go, English-only) | structural (strip blanks/`--`) | n/a |
| npm / pnpm / cargo / go / docker / kubectl / tsc / eslint / pytest / mvn / gradle / … (~140) | **No** — Go/Rust/Node/Python/Java/Ruby/PHP toolchains emit English regardless of `LANG` | — | n/a |

So localizing "all tools" would be almost entirely dead regex: the long tail
emits English in any locale, and the structural filters (grep, git-log, ls, …)
are already locale-agnostic by construction.

## Why no Romanian

The two tools worth localizing **do not ship Romanian translations**:

- **git** translates to 18 languages (bg, ca, de, el, es, fr, ga, id, is, it,
  ko, pl, pt_PT, ru, sv, tr, uk, vi) — **Romanian is not one of them**. In a
  `ro_RO` locale `git status` falls back to English.
- The **.NET CLI / MSBuild / VSTest** localize to ~14 languages (cs, de, es, fr,
  it, ja, ko, pl, pt-BR, ru, tr, zh-Hans/Hant) — **no Romanian** either.

Romanian therefore only ever appears in **user data** (commit messages, file
contents, Jira/Miro issue text) — which must be **preserved**, not filtered.
That long-tail, locale-agnostic case is handled by the **context-mode** layer
(`omp plugin install context-mode`), whose FTS5/BM25 indexing is
language-independent — not by per-language regex here.

## Azure DevOps CLI / Jira / Miro / acli

These are **not** localized-CLI-output problems:

- **`az devops`** and **`acli`** (the official Atlassian CLI) emit JSON / tables
  with English, language-neutral keys; neither is translated. ctx-wire
  localization is N/A — the bundled `acli.toml` is a **structural** filter (strip
  blanks, cap, truncate) like `grep`/`jira`, plus a secret `replace` (below).
- **Jira / Miro** are also reachable as **MCP servers** (JSON payloads, English
  field names), not shell commands — ctx-wire's command filters never see them.
  See "Compressing MCP output" below; their *values* may be fr/ro but are data to
  keep, not chrome to strip.

## Secret scrubbing (what's covered, and the ATATT gap)

ctx-wire scrubs secrets from **all** command output via a built-in (non
user-configurable) pass. It already redacts: PEM private keys; JWTs; AWS
(`AKIA`/`ASIA`), Google (`AIza`), **GitHub** (`ghp_/gho_/ghu_/ghs_/ghr_/
github_pat_`), Slack, Stripe, OpenAI/Anthropic, Vault, PyPI tokens;
`Authorization: <scheme> <secret>` headers; `scheme://user:password@host` URLs;
and secret-ish `key=value` / `--secret-flag value` pairs.

So **GitHub tokens** and **Azure DevOps PATs / Atlassian tokens in the usual auth
forms** (Basic header, `https://user:pat@…` URL, `token=…` assignment) are
already scrubbed. The one shape it doesn't know is a **bare `ATATT…` Atlassian
API token** (no matching prefix). Since the scrub rules aren't user-extensible,
`acli.toml` adds a filter `replace` that redacts `ATATT…` from acli output. To
scrub bare ATATT tokens everywhere (not just acli output), upstream an `ATATT`
entry to ctx-wire's `internal/scrub/scrub.go` token alternation + literal anchors.

## Compressing MCP output

ctx-wire's PATH shims only see **shell commands**, not MCP traffic. The big
JSON from the Atlassian / Miro / GitHub MCP servers is compressed by two
mechanisms here:

- **context-mode** (installed by `install.sh`) registers on `tool_result`, so it
  sandboxes and indexes **MCP output** the same as shell output — locale-agnostic,
  no per-server config. This covers the environment-managed servers (Atlassian,
  Miro, GitHub) that are **not** in any MCP config file we control, so they can't
  be wrapped directly.
- **`ctx-wire mcp-wrap`** for servers you *do* define (e.g. a self-hosted server
  in a project `.mcp.json`): `ctx-wire mcp-wrap install --compress -- <server cmd>`
  rewrites that entry to relay through ctx-wire (measures per-tool token cost and,
  with `--compress`, trims verbose snapshots). Revert with `mcp-wrap uninstall`.
  We deliberately do **not** wrap any project-defined MCP server by default — that
  would couple that server to a ctx-wire install (which may be unavailable);
  opt in manually if wanted.

## Escape hatch: pin the locale

If you'd rather keep everything English (and skip localized filters entirely),
export `DOTNET_CLI_UI_LANGUAGE=en` and `LC_MESSAGES=C` for the agent's shell so
git/dotnet always emit English and the upstream filters apply unchanged. The
EN+FR pack is the better default when developers genuinely work in French.

## Updating the French strings

Re-extract from upstream localization when tool versions change:

- git:     `git/git@master:po/fr.po`
- MSBuild:  `dotnet/msbuild@main:src/Build/Resources/xlf/Strings.fr.xlf`
- VSTest:   `microsoft/vstest@main:src/vstest.console/Resources/xlf/Resources.fr.xlf`
- MTP:      `microsoft/testfx@main:src/Platform/Microsoft.Testing.Platform/Resources/xlf/PlatformResources.fr.xlf`
- NuGet:    `NuGet/NuGet.Client@dev:src/NuGet.Core/NuGet.Commands/xlf/Strings.fr.xlf`
- SDK/tool: `dotnet/sdk@main:src/Cli/dotnet/Commands/xlf/CliCommandStrings.fr.xlf`

Then run `ctx-wire verify` (or the bundled `scripts/verify-filters.py`).

### Microsoft.Testing.Platform (MTP) vs VSTest

`dotnet test` can run on either the classic **VSTest** console (single-line
`Passed! - Failed: 0, …` summary) or the newer **MTP** runner (multi-line
`Test run summary:` block). The `dotnet-test` filter handles **both**. Because an
MTP test project is a plain console app with an entry point, it is also run via
**`dotnet run`** — so the `dotnet-run` filter collapses an all-passed MTP summary
too (and preserves failures).
