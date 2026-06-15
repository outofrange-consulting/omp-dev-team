# token-diet

> 🌐 **English** · [Français](README.fr.md)

Aggressive **token reduction** for OMP dev teams. Bundles three best-in-class
external token savers and wires them into OMP the native way — on top of what OMP
already does (compaction, `astGrep`/`summarizeCode`, provider prompt caching), not
in place of it.

| Layer | What | Win | Upstream |
|---|---|---|---|
| **ctx-wire** | transparent CLI proxy that filters command **output** + scrubs secrets (full logs kept on disk) | big cuts on `git`/build/test/lint noise | [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire) |
| **CodeGraph** | MCP symbol/call graph — query instead of grep+read | ~96% on "who calls X / impact / architecture" | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) |
| **caveman** | terse, fragment-style **output** (on demand) | ~65% output tokens | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | write **less code** — YAGNI / laziest-senior-dev (on demand) | ~80–94% less code; fewer tokens now + every future turn | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |

## Install

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installs ctx-wire + codegraph, indexes your repos,
                                     # and turns everything on. Restart omp afterwards.
```

**Active by default after `install.sh`** — no manual flags: ctx-wire shims compress
command output, the CodeGraph MCP server is enabled, and the skills are turned on.
`install.sh` prompts for the **root of your sources** (a directory of many repos)
and indexes each git repo it finds (`--sources-root=PATH`, `--depth=N`).

## How it's wired into OMP

- **ctx-wire** → installed by `install.sh`, then **`ctx-wire shims install`** drops
  transparent wrappers into `~/.local/bin` (first on PATH, inherited by OMP's bash
  tool) so the agent runs commands normally — **no prefix** — and their output is
  filtered + secret-scrubbed before it hits context (full logs kept on disk).
  (`ctx-wire init claude` only wires Claude Code, not OMP, so we use shims.)
  `ctx-wire gain` shows savings; `ctx-wire doctor` verifies; `ctx-wire mcp-wrap` can also compress
  MCP-server output. Replaces the earlier RTK integration.
- **CodeGraph** → an MCP server (`.mcp.json`, `codegraph serve --mcp`, **enabled by
  default**) exposing `codegraph_search/node/callers/callees/explore/impact/files/status`.
  See `skill://codegraph`. Auto-syncs on file changes.
- **skills** → `install.sh` appends `config.snippet.yml` to `~/.omp/agent/config.yml`
  (`skills.enableSkillCommands: true`) so `/caveman`, `/yagni` and `skill://codegraph`
  are available (plugin-provider skills need this toggle). `--no-config` to skip.
- **caveman** → a native OMP skill (`/caveman`, levels lite/full/ultra) rather
  than the upstream installer, so it's first-class in OMP. See `skill://caveman`.
- **yagni** → a native OMP skill (`/yagni`, levels lite/full/ultra/off) porting
  the ponytail "laziest senior dev" YAGNI discipline: a *do-I-even-need-this*
  ladder + review/audit/debt modes. Lazy ≠ negligent — security/validation/data-
  loss/a11y/tests are never cut (and it won't edit `.feature` specs to dodge
  work). See `skill://yagni`.

## What OMP already does (so you don't double up)

Compaction/handoffs (history summarization), native AST tools (`astGrep`,
`astEdit`, `summarizeCode`, `blockRangeAt`), and provider prompt/context caching.
This plugin fills the remaining gaps: raw command output, persistent cross-file
symbol graph, and verbose model output. See `skill://token-diet` for the full
decision guide.

## Notes

- Pairs naturally with **copilot-preset** (cheap per-token models) — fewer tokens
  × cheaper tokens.
- The CodeGraph entry previously sitting (disabled) in `dev-team/.mcp.json` is
  now centralized here with the correct `serve --mcp` invocation.
- Independent of the other plugins; install only what you want.
