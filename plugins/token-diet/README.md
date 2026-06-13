# token-diet

> 🌐 **English** · [Français](README.fr.md)

Aggressive **token reduction** for OMP dev teams. Bundles three best-in-class
external token savers and wires them into OMP the native way — on top of what OMP
already does (compaction, `astGrep`/`summarizeCode`, provider prompt caching), not
in place of it.

| Layer | What | Win | Upstream |
|---|---|---|---|
| **RTK** | Rust Token Killer — CLI proxy that compresses command **output** | 60–90% on `git`/`grep`/`find`/`test` | [rtk-ai/rtk](https://github.com/rtk-ai/rtk) |
| **CodeGraph** | MCP symbol/call graph — query instead of grep+read | ~96% on "who calls X / impact / architecture" | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) |
| **caveman** | terse, fragment-style **output** (on demand) | ~65% output tokens | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |

## Install

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installs rtk + codegraph, then asks for your
                                     # sources ROOT and indexes EVERY git repo under it
```

`install.sh` prompts for the **root of your sources** (a directory containing many
repos) and indexes each git repo it finds (`--sources-root=PATH`, `--depth=N`), so
any repo is ready the moment you open it. Then enable the CodeGraph MCP server
(ships `enabled: false`): set `mcpServers.codegraph.enabled = true` in your merged
`.mcp.json`.

## How it's wired into OMP

- **RTK** → an **always-on rule** (`rules/token-tools.md`) tells the agent to run
  noisy shell commands as `rtk <cmd>`. RTK is CLI-only (no MCP); OMP isn't a
  target of `rtk init`, so the rule is the integration. It degrades gracefully if
  `rtk` isn't installed.
- **CodeGraph** → an MCP server (`.mcp.json`, `codegraph serve --mcp`) exposing
  `codegraph_search/node/callers/callees/explore/impact/files/status`. See
  `skill://codegraph`. Auto-syncs on file changes.
- **caveman** → a native OMP skill (`/caveman`, levels lite/full/ultra) rather
  than the upstream installer, so it's first-class in OMP. See `skill://caveman`.

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
