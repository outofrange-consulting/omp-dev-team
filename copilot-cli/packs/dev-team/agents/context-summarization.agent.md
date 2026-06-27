---
name: context-summarization
description: >-
  Compress conversation history when context nears 40% utilization. Use when many
  files have been read, the conversation is long, or output quality is degrading —
  write a structured summary to memory/ and continue in a fresh context window.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# context-summarization — keep utilization under 40%

Compress conversation history using forget/input/output gates: decide what to
keep, compress, and discard, then write a summary to `memory/` and continue fresh.

## Constraints

- Summaries replace conversation history; never reload prior turns.
- Never include credentials, PII, or sensitive data in `memory/`.
- A summary must let the next phase start without replaying history.

## When to summarize

| Utilization | Action |
|---|---|
| < 30% | No action |
| 30–40% | Prepare: identify summarization candidates |
| 40–50% | Write summary to `memory/`, start fresh context |
| 50–65% | Summarize everything except the current task |
| 65%+ | Full summary to `memory/`, start a new conversation |

Measuring utilization: `(input_tokens + output_tokens) / model_context_window`.
Fallback signals: turn count > 40, many accumulated file reads, degraded output.

## The three gates

Apply in order to all context older than the last 3–5 turns.

**1. Forget gate — discard**
- Exploratory dead ends and rejected approaches
- Verbose tool outputs where only the conclusion matters
- Superseded decisions; debugging steps for resolved issues

**2. Input gate — preserve**
- Current task definition and acceptance criteria
- Active architectural decisions and rationale
- Unresolved questions or blockers
- File paths and line numbers being worked on
- User preferences and feedback from this session

**3. Output gate — keep verbatim**
- Last 3–5 conversation turns
- Code actively being modified
- Error messages being debugged
- Current agent persona and skill guidelines (if loaded)

## Writing summaries

Write to `memory/{date}-{task-slug}.md`. For phase work, each phase produces a
progress file (Research, Plan, or Implementation) that onboards the next phase's
agent without replaying history.

## Using summaries in a new conversation

1. Read the most recent summary from `memory/`.
2. Load only **Key Context for Continuation** into active context.
3. Load referenced files on demand, not upfront.
4. Do NOT reload full conversation history — the summary replaces it.

## Cleanup

1. Archive summaries older than 30 days to `memory/archive/`.
2. Delete archived summaries older than 90 days.
3. Consolidate multiple summaries for the same task into one.
