# Upstream extraction — the OMP / pi runtime (distinct from agentic-dev-team)

The `docs/upstream-v7*.md` files track **`bdfinst/agentic-dev-team`** — the
prompt/skill framework this plugin set is ported from. They do **not** track the
**OMP / pi runtime** (`@oh-my-pi/pi-coding-agent`) the plugins actually run on.
That left a gap: several skills carry assumptions from a much older OMP (or from
the Claude-Code era before the port), while current OMP exposes capabilities the
repo wasn't using. This doc tracks the runtime axis.

**Runtime surveyed:** `@oh-my-pi/pi-coding-agent@17.1.4` (inspected by
`bun add`-ing the package and reading `src/` + the published `dist/types/`).
Re-verify when bumping OMP — 17.0.0 REMOVED settings this repo depended on
(`tools.discoveryMode`, `tools.essentialOverride`, `mcp.discoveryMode`), and OMP
now deletes them from config on load, so a stale assumption here is silent.

## Capabilities now available to extensions (that the repo under-used)

| Capability | Where | Status in repo |
|---|---|---|
| **Per-turn token usage incl. cache split** — `turn_end`/`message_end` carry `message.usage` (`input`, `output`, **`cacheRead`**, **`cacheWrite`**, `reasoningTokens`, `cttl`, `cost.total`) | `extensibility/extensions/types.ts` (events) → pi-catalog `Usage` | **Now used** by token-diet `cache-meter` (PR #20). Previously assumed absent. |
| **Statusline** — `ctx.ui.setStatus(key, text)` writes the footer/status bar | `extensibility/extensions/types.ts` `ExtensionUIContext` | **Now used** by token-diet `cache-meter` footer (PR #21). |
| **Provider quota** — `after_provider_response` event carries `headers` (Anthropic `ratelimit-*`) | `extensibility/extensions/types.ts` | **Now used** by `cache-meter` (best-effort). |
| **Native cross-session memory (Mnemopi)** — SQLite + embeddings, tools `recall`/`retain`/`reflect`/`memory_edit`, auto-recall/retain | `mnemopi/*`, `memory-backend/*`, `tools/memory-*.ts` | **OFF by default** (`memory.backend: "off"`). Documented in `docs/mnemopi-coexistence.md`. |
| Rich event surface — `turn_start/end`, `message_start/update/end`, `before/after_provider_response`, `goal_updated`, `auto_compaction_*`, `tool_*`, `context` | `ExtensionAPI.on(...)` in `types.ts` | Partially used (guards/dedup/compress/meter). Room to grow. |

## Stale assumptions (carried from old OMP / Claude Code) — RESOLVED

The three skills below were reconciled with current OMP (the fixes are
documentation/prose only — no extension behavior changed):

1. **`plugins/dev-team/skills/cost-report/SKILL.md`** — ✅ fixed. The stale "Token
   usage is not available to hooks" lead was replaced with a two-source
   description (Live: `turn_end.message.usage` via token-diet `cache-meter` /
   `/cache-health`; Post-hoc: the transcript meter, flagged as aspirational since
   its `cost_meter.py` is absent).
2. **`plugins/dev-team/skills/freeze/SKILL.md` + `unfreeze/SKILL.md`** — ✅ fixed.
   Both rewritten to document the real `freeze-guard` extension: it owns
   `/freeze`/`/unfreeze`, stores `{ "globs": [...] }` out-of-tree at
   `~/.omp/state/dev-team/<repoId>/freeze.json` (`OMP_DEVTEAM_STATE_DIR` to
   relocate), and enforces via the `tool_call` hook. The obsolete
   `hooks/freeze-state.json` + `pre-tool-guard.sh` flow was removed.
3. **`plugins/dev-team/skills/handoff-policy/SKILL.md`** — ✅ fixed. The
   utilization measurement now prefers OMP's live `getContextUsage()` `percent`
   (already surfaced by `telemetry.ts` via `/cost-report`), with the manual
   `(input+output)/window` estimate kept as a fallback.

## How to refresh this doc

```sh
mkdir -p /tmp/omp-probe && cd /tmp/omp-probe
bun add @oh-my-pi/pi-coding-agent@latest
# inspect node_modules/@oh-my-pi/pi-coding-agent/src/extensibility/extensions/types.ts
# (events + ExtensionAPI), src/mnemopi, src/config/settings-schema.ts
```

Bump the surveyed version at the top, re-check the capability table and the stale
list, and prune anything since fixed.
