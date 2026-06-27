# Upstream extraction — the OMP / pi runtime (distinct from agentic-dev-team)

The `docs/upstream-v7*.md` files track **`bdfinst/agentic-dev-team`** — the
prompt/skill framework this plugin set is ported from. They do **not** track the
**OMP / pi runtime** (`@oh-my-pi/pi-coding-agent`) the plugins actually run on.
That left a gap: several skills carry assumptions from a much older OMP (or from
the Claude-Code era before the port), while current OMP exposes capabilities the
repo wasn't using. This doc tracks the runtime axis.

**Runtime surveyed:** `@oh-my-pi/pi-coding-agent@16.2.2` (inspected by
`bun add`-ing the package and reading `src/`). Re-verify when bumping OMP.

## Capabilities now available to extensions (that the repo under-used)

| Capability | Where | Status in repo |
|---|---|---|
| **Per-turn token usage incl. cache split** — `turn_end`/`message_end` carry `message.usage` (`input`, `output`, **`cacheRead`**, **`cacheWrite`**, `reasoningTokens`, `cttl`, `cost.total`) | `extensibility/extensions/types.ts` (events) → pi-catalog `Usage` | **Now used** by token-diet `cache-meter` (PR #20). Previously assumed absent. |
| **Statusline** — `ctx.ui.setStatus(key, text)` writes the footer/status bar | `extensibility/extensions/types.ts` `ExtensionUIContext` | **Now used** by token-diet `cache-meter` footer (PR #21). |
| **Provider quota** — `after_provider_response` event carries `headers` (Anthropic `ratelimit-*`) | `extensibility/extensions/types.ts` | **Now used** by `cache-meter` (best-effort). |
| **Native cross-session memory (Mnemopi)** — SQLite + embeddings, tools `recall`/`retain`/`reflect`/`memory_edit`, auto-recall/retain | `mnemopi/*`, `memory-backend/*`, `tools/memory-*.ts` | **OFF by default** (`memory.backend: "off"`). Documented in `docs/mnemopi-coexistence.md`. |
| Rich event surface — `turn_start/end`, `message_start/update/end`, `before/after_provider_response`, `goal_updated`, `auto_compaction_*`, `tool_*`, `context` | `ExtensionAPI.on(...)` in `types.ts` | Partially used (guards/dedup/compress/meter). Room to grow. |

## Stale assumptions to fix (carried from old OMP / Claude Code)

These are accuracy fixes, listed as follow-ups (each is a behavioral-doc change
that deserves its own small review, so they are **not** bundled here):

1. **`plugins/dev-team/skills/cost-report/SKILL.md:18`** — leads with "Token
   usage is not available to hooks." It is, now (`turn_end.message.usage`). A
   "Note (current OMP)" block was already appended (PR #20) and points to
   `/cache-health`, but the stale lead line and the never-present `cost_meter.py`
   it documents should be reconciled (either implement a live meter over
   `turn_end.usage` or rewrite the skill around `cache-meter`).
2. **`plugins/dev-team/skills/freeze/SKILL.md:37`** (and `unfreeze/SKILL.md`) —
   instructs writing/deleting `hooks/freeze-state.json`. The live `freeze-guard.ts`
   extension actually keys state out-of-tree at
   `~/.omp/state/dev-team/<repoId>/freeze.json` (`extensions/lib/shared.ts`). The
   skill prose lags the extension; align them so the documented path matches.
3. **`plugins/dev-team/skills/context-summarization/SKILL.md:28`** — computes
   context utilization by hand (`(input+output)/window`, with a "turn count > 40"
   fallback). OMP now exposes live `ctx.getContextUsage()` (already used by
   dev-team `telemetry.ts:42`); the summarization gate could read it directly
   instead of estimating.

## How to refresh this doc

```sh
mkdir -p /tmp/omp-probe && cd /tmp/omp-probe
bun add @oh-my-pi/pi-coding-agent@latest
# inspect node_modules/@oh-my-pi/pi-coding-agent/src/extensibility/extensions/types.ts
# (events + ExtensionAPI), src/mnemopi, src/config/settings-schema.ts
```

Bump the surveyed version at the top, re-check the capability table and the stale
list, and prune anything since fixed.
