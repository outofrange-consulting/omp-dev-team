---
name: handoff-policy
description: Decide WHAT survives a context boundary and WHERE it is written — the Three Gates (forget / input / output), the memory/ artifact contract, and the fork-vs-continue rubric. The mechanics of compacting, handing off, forking and branching are OMP builtins; this skill is the policy layer over them. Use before /handoff or /compact, at a phase transition, when context utilization climbs, or when deciding whether to fork the session or start a fresh one.
role: orchestrator
user-invocable: true
---

# Handoff Policy

**OMP already ships the mechanics.** This skill does not reimplement them:

| you need | native surface |
|---|---|
| hand this session's context to a new one | `/handoff [focus instructions]` |
| shrink the live context in place | `/compact [soft \| remote \| snapcompact] [focus]` |
| branch from an earlier message and try another route | `/fork` |
| move between branches of the session tree | `/tree` |
| see what is actually filling the window | `/context`, or the `context_pct` statusline segment |
| persistent recall across sessions | `memory.backend` (`off` \| `local` \| `hindsight` \| `mnemopi`; default `off`) |

What is **ours**, and what this file is for: the *policy* those commands do not
encode — which content is worth carrying, what shape it must be written in, and
whether to continue, compact, fork, or start fresh.

## Constraints

- A summary **replaces** conversation history. Never reload prior turns after
  writing one.
- Never write credentials, tokens, PII, customer data, or full `.env` contents
  into `memory/`. It is a durable, usually-committed artifact directory —
  redaction is the last gate before anything lands there (see Redaction pass).
- A summary is only good enough if the **next** phase can start from it without
  replaying history. If you would need the transcript, the summary is incomplete.

> If you enable OMP's native memory (`memory.backend` other than `off`), its
> auto-recall re-injects material into the context this policy just deflated. See
> `docs/mnemopi-coexistence.md` — by default the backend is `off` and these
> `memory/` files are authoritative.

## The Three Gates

Apply in order to everything older than the last 3-5 turns. These gates are the
substance of a good `focus` argument to `/compact` or `/handoff`, and of anything
you write to `memory/`.

### 1. Forget gate — discard

- Exploratory dead ends and rejected approaches
- Verbose tool output where only the conclusion mattered
- Superseded decisions
- Debugging steps for issues that are now resolved

### 2. Input gate — preserve, compressed

- The current task definition and its acceptance criteria
- Active architectural decisions **and their rationale** (a decision without its
  rationale gets relitigated)
- Unresolved questions and blockers
- File paths and line numbers under active work
- User preferences and corrections from this session

### 3. Output gate — keep verbatim

- The last 3-5 turns
- Code being modified right now
- Error messages currently being debugged
- The active agent persona and any loaded skill guidance

## Redaction pass

Run this *after* the gates, *before* writing. It is cheap and it is the only
thing standing between a leaked secret and a committed file.

1. Scan the candidate summary for: API keys and tokens, connection strings,
   `Authorization:` headers, private keys, customer names/emails/ids, and any
   `.env` line you quoted verbatim.
2. Replace each with a **description of what it was**, never a partial value —
   `<datadog API key, in .env as DD_API_KEY>` beats `dd_api_key: 3f9a…` (a prefix
   is still an identifier).
3. If you cannot summarise a value without reproducing it, say why it mattered
   and drop the value entirely.

Note that native `secrets` scanning protects the *live context*, not a file you
author. This pass is yours.

## Fork, continue, compact, or start fresh

Pick by what you need to preserve, not by how full the window is:

| situation | do this | why |
|---|---|---|
| Same task, context is heavy, all decisions still stand | `/compact` with a focus line built from the Input gate | Cheapest. Keeps one lineage; nothing to reconcile. |
| Same task, you want to try a *different* approach from a known-good point | `/fork` at that message, then `/tree` to compare | Both branches stay reachable — you can abandon one without losing the other. Do **not** hand-write a summary for this; the branch *is* the record. |
| Phase boundary (research → plan → build), same overall task | Write the phase progress file, then `/handoff` | The next phase needs a clean window and a different agent mix. The progress file is what onboards it. |
| New task, or the current one is finished/abandoned | Write the task summary, then a fresh session | Carrying a finished task's context into a new one is pure cost. |
| Output quality is degrading and you cannot say what is in the window | `/context` first, then decide | Do not compact blind. Compaction discards the warm prompt cache; the next request re-reads the new context at full input price, so an unnecessary compaction is a real cost, not a free tidy-up. |

Signals that it is time, in order of reliability: the `context_pct` statusline
segment or `/context` report; then coarse proxies — turn count past ~40, a large
accumulation of file reads, or answers that start contradicting earlier ones.

## The `memory/` artifact contract

This is the part no native command provides, and the reason `memory/` exists as a
directory in the repo rather than as harness state.

- **Task summary** → `memory/{date}-{task-slug}.md`
- **Phase progress files** → `memory/research-progress-*.md`,
  `memory/plan-progress-*.md`, `memory/implementation-progress-*.md`
- **Decision log** → `memory/decisions.md` (append-only)
- **Review summaries** → `memory/review-summaries/<date>-<short-sha>.md`
  (written by the `review-summary` skill)

Shapes for each live in [`references/summary-templates.md`](references/summary-templates.md).
Use them exactly — `/continue` parses these files to find the resume point, and a
free-form summary is a summary `/continue` cannot use.

### Consuming them in a new session

1. Read the most recent artifact from `memory/`.
2. Load only its **Key Context for Continuation** into active context.
3. Load referenced files on demand, not upfront.
4. Do **not** reload conversation history — the artifact replaces it. That is the
   whole trade.

### Cleanup

Archive artifacts older than 30 days to `memory/archive/`; delete archived ones
older than 90 days; consolidate multiple artifacts for the same task into one.

## Notes

- Renamed from `context-summarization`. The old skill also specified *how* to
  compress and when to start a fresh window — work OMP now does natively via
  `/compact`, `/handoff`, `/fork`, `/tree` and `memory.backend`. Only the parts
  the harness has no opinion about were kept: the gates, the redaction pass, the
  fork-vs-continue rubric, and the artifact contract.
- Its utilization table (fixed 30/40/50/65% bands) is gone too. Compaction
  thresholds are a `compaction.*` setting, not something a skill should
  second-guess; the rubric above keys off what you need to preserve instead.
