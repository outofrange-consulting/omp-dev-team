---
name: context-management
description: >-
  Manage the working context window — at task start, select the minimum viable set
  of agents/skills to load (context-loading-protocol); mid-task, compress history
  when utilization gets high (context-summarization). Use to decide what to load or
  when output quality drops / context fills up.
---

# Context management (load minimal · summarize)

- **context-loading-protocol** — decide which agents/skills to load for a task;
  compute the minimum viable context. See `references/context-loading-protocol.md`.
- **context-summarization** — compress conversation history when context utilization
  is high. See `references/context-summarization.md`.
