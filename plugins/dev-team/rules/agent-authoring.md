---
description: When authoring agents, declare a model tier and the minimum tool set
globs:
  - ".omp/agents/**/*.md"
---

**Every agent file must declare its tier and a minimal tool set.**

- `model:` frontmatter declares the tier (cheap end split by **workload shape** —
  pick by the *shape* of the work, not only its difficulty):
  - `pi/smol` — **nano**: pure lexical/structural pattern matching + checklist
    review + input-bound scan, no code-semantics or tool-use. Routed via
    `modelRoles.smol` (default Haiku; copilot-preset → gpt-5-mini).
  - `pi/task` — **code**: cheap work needing code semantics or agentic tool-use
    (post-plan implementation, structural code-semantic review). Routed via
    `modelRoles.task` (default Haiku; copilot-preset → mai-code-1-flash).
  - `claude-sonnet-4-6` — **balanced** semantic / cross-file analysis.
  - `claude-opus-4-8` — **deep** high-stakes cross-file reasoning / synthesis.
- Grant only the tools the agent needs (OMP names: `read, search, find, edit,
  write, bash, task, web_search, ask`). Review agents are typically
  `read, search, find` only.
- Agents that dispatch others declare `spawns` (e.g. `spawns: explore` or `"*"`).
- Review/verdict agents set `blocking: true` so the orchestrator waits on them.
- Keep agents lean — the registry tracks token budgets. See
  `skill://dev-team-knowledge/agent-registry.md`.
