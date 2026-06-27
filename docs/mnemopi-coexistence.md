# Mnemopi coexistence — native OMP memory vs dev-team's `memory/` files

OMP 16.x ships a native cross-session memory subsystem, **Mnemopi** (SQLite +
local embeddings, tools `recall`/`retain`/`reflect`/`memory_edit`). The
`dev-team` plugin independently implements its own cross-session memory as
LLM-authored Markdown under a project-local `memory/` directory. This note
records how the two relate and which one is authoritative, because the repo
otherwise never mentions Mnemopi exists.

## TL;DR

**Mnemopi is OFF by default, so there is nothing to do by default and no
conflict today.** `dev-team`'s `memory/` files are the cross-session store. Only
if you explicitly set `memory.backend: "mnemopi"` do the two start to overlap —
see [If you enable Mnemopi](#if-you-enable-mnemopi-anyway).

## The two stores

| | dev-team `memory/` (default) | OMP Mnemopi (opt-in) |
|---|---|---|
| Form | LLM-authored **Markdown** | **SQLite** + local embeddings (knowledge graph) |
| Location | project-local `memory/` (git-ignored) | `~/.omp/agent/memories/mnemopi/mnemopi.db` (user-global, per-cwd bank) |
| Written by | orchestrator + skills (`memory/decisions.md`, phase progress files) | auto-retain every N turns + `retain` tool |
| Injected | the agent **reads** files on `/continue` / phase start | **auto-injected** into the system prompt on turn 1 (when enabled) |
| Default | **on** (it's just files) | **off** (`memory.backend: "off"`) |
| Transparency | git-diffable, human-readable, in-tree | opaque DB, out-of-tree |

Sources: OMP default `memory.backend: "off"` (`settings-schema.ts`); auto-recall
into the base system prompt (`mnemopi/state.ts` `maybeRecallOnAgentStart` →
`refreshBaseSystemPrompt`); compaction co-injection (`backend.ts`
`preCompactionContext`). dev-team store: `orchestrator.md` (`memory/decisions.md`,
progress files), `context-summarization/SKILL.md`, `continue/SKILL.md`.

## Authoritative store: dev-team `memory/` (keep Mnemopi off)

For this repo, the project-local `memory/` files remain the source of truth, and
Mnemopi is left at its default (off). Rationale:

- **Transparent & git-diffable.** `memory/decisions.md` and the phase-progress
  files are plain Markdown a human can read and a diff can review — matching the
  plugin's transparent, auditable ethos. Mnemopi's store is an opaque SQLite DB.
- **No hidden injection.** dev-team memory is pulled in **explicitly** (the agent
  reads files on `/continue` / phase start). Mnemopi auto-injects a `<memories>`
  block into the system prompt — invisible context the plugin doesn't control.
- **Aligns with deflation.** `context-summarization` exists to push context
  **below 40%** and "**replace conversation history; never reload prior turns**"
  (`context-summarization/SKILL.md:14`). Mnemopi's job is the opposite —
  remember and re-inject — so leaving it off avoids working against the gate.

This stance is **reversible**: it documents the current default and adds no new
behavior. Flip it by adopting the split below.

## If you enable Mnemopi anyway

Setting `memory.backend: "mnemopi"` turns on, by default, both `autoRecall` and
`autoRetain`. Two real interactions with dev-team then appear:

1. **Re-inflation vs summarization.** On turn 1, Mnemopi recalls up to
   `recallLimit` (8) memories and splices a `<memories>` block (≤
   `injectionTokenLimit`, 5000 tokens) into the base system prompt; on every
   compaction, `preCompactionContext` pushes recalled memory into the
   summarization prompt. That re-introduces exactly what
   `context-summarization`'s "never reload" rule just discarded, working against
   the 40% ceiling.
2. **Content duplication.** The same decision can land in both
   `memory/decisions.md` and Mnemopi, with no dedup or cross-reference.

There is **no filesystem collision** — Mnemopi writes to
`~/.omp/agent/memories/…`, never the project `memory/` dir (unless you override
`mnemopi.dbPath` into the repo).

**If you want Mnemopi on, pick one source of truth:**

- **Mnemopi as a manual tool only** — set `mnemopi.autoRecall: false` and
  `mnemopi.autoRetain: false`. The agent uses `recall`/`retain` deliberately;
  nothing auto-injects, so summarization keeps its deflation. `memory/` stays
  authoritative for phase progress.
- **Mnemopi owns durable memory** — let it auto-recall/retain durable facts, and
  stop duplicating long-lived decisions into `memory/decisions.md` (keep
  `memory/` for phase-transient progress only). Accept the re-injection cost as
  the price of native recall.

Avoid the middle ground (Mnemopi fully auto **and** `memory/decisions.md` as the
log) — that is the double-write + re-inflation footgun this note exists to flag.

## See also

- `docs/upstream-omp-runtime.md` — the OMP 16.x runtime capabilities the repo
  didn't track (Mnemopi is one of them).
- `plugins/dev-team/skills/context-summarization/SKILL.md` — the deflation gate.
