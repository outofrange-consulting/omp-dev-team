---
description: When authoring agents, declare a model tier and the minimum tool set
globs:
  - ".omp/agents/**/*.md"
---

**Every agent file must declare its tier and a minimal tool set.**

- `model:` frontmatter declares the tier:
  - `pi/smol` — small/local tier (lexical/structural pattern matching, checklist
    review). Routed to the local model via `modelRoles.smol`.
  - `claude-sonnet-4-6` — balanced semantic analysis.
  - `claude-opus-4-8` — deep cross-file reasoning / synthesis.
- Grant only the tools the agent needs (OMP names: `read, search, find, edit,
  write, bash, task, web_search, ask`). Review agents are typically
  `read, search, find` only.
- Agents that dispatch others declare `spawns` (e.g. `spawns: explore` or `"*"`).
- Review/verdict agents set `blocking: true` so the orchestrator waits on them.
- Keep agents lean — the registry tracks token budgets. See
  `skill://agent-skill-authoring` and `skill://dev-team-knowledge/agent-registry.md`.
