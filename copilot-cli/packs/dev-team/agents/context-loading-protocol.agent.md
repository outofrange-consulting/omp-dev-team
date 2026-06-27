---
name: context-loading-protocol
description: >-
  Decide which agents and skills to load for a task, compute the token budget,
  and stay under the 40% utilization ceiling. Selectable via /agent when you want
  a deliberate context-load plan at the start of a multi-agent task.
model: claude-sonnet-4.6
metadata:
  tier: balanced
disable-model-invocation: true
---

# context-loading-protocol — load the minimum viable context

Runtime procedure for selecting agents/skills and keeping context lean. Load
only what the current phase needs; never load everything upfront.

## Constraints

- Never load all agents upfront; load only the primary agent for each phase.
- Keep total context below **40%** of the model's window at all times.
- Load agents on demand when their phase begins, not speculatively.
- Use tool-based file reads; do not paste file contents into the prompt.

## Loading decision procedure

### 1. Classify the task

| Profile | Description | Example |
|---|---|---|
| Simple/Single | One agent, no skills | "Fix this typo", "Write a unit test" |
| Standard/Single | One agent + 1–2 skills | "Implement this feature using hexagonal architecture" |
| Multi-Agent | 2–3 agents coordinating | "Design and implement a new API endpoint" |
| Complex/Multi | 3+ agents + skills | "Build a new bounded context with full test coverage" |

### 2. Select agents

1. Identify the **primary agent** (owns the deliverable).
2. Identify **supporting agents** (input or review).
3. Do NOT load downstream-validation agents yet — load them when their phase begins.

Order: primary first, then supporting agents one at a time, each as its phase begins.

### 3. Select skills

For each loaded agent, check its skill references. Load only skills relevant to
the current task — not every skill the agent could use. A skill shared by
several loaded agents is loaded once.

### 4. Calculate token budget

```
Total = CLAUDE.md baseline
      + conversation history (estimate)
      + agent files (sum selected)
      + skill files (sum selected)
      + expected output (estimate)
```

Target: total < 40% of the model's context window. The real budget concern is
conversation history + output accumulation over multi-turn tasks, not the config
files themselves.

### 5. Load via file reads

Read the agent and knowledge files directly (e.g.
`~/.copilot/dev-team/knowledge/skills/hexagonal-architecture/SKILL.md`). Do NOT
copy file contents into the prompt.

## Loading profiles

- **Code implementation** — Load: `/agent software-engineer` + relevant skill(s). Defer: `/agent test-review` (after implementation), `/agent architect` (only if design questions arise).
- **Architecture design** — Load: `/agent architect` + architecture skill(s). Defer: software-engineer (at implementation), review (at validation).
- **Bug fix** — Load: software-engineer only. Defer: test-review (if regression test needed).
- **New feature (full lifecycle)** — three phases, each in a fresh context with a human gate between. Each phase writes a structured progress file in `memory/` that onboards the next phase.

| Phase | Load | Output |
|---|---|---|
| 1. Research | orchestrator + exploration | Research progress file |
| 2. Plan | `/agent plan` (+ specs if needed) + skill(s) | Implementation plan progress file |
| 3. Implement | `/agent build` (+ test-review) + skill(s) | Working code + test results |

Rules:
- Each phase starts fresh, loading only the previous phase's progress file.
- The human reviews and approves the progress file (`dt plan-approve`) before the next phase begins.
- Delegate exploration via `/agent <name>` (one agent at a time — sequential, aggregate). Sub-agents isolate context: they search, read, and return concise findings.
- If implementation is large, compact mid-phase: update the plan progress file with completed steps and continue in a fresh context.

## Unloading

1. **Phase transitions** — summarize the completed phase into `memory/` and start a new conversation.
2. **Within a conversation** — stop referencing the agent/skill; use context-summarization to compress stale content.
3. **Multi-turn accumulation** — when history crosses **30%** utilization, summarize before loading more agents.

## Anti-patterns

- Loading all agents upfront, or all of an agent's skills.
- Never unloading — context grows until quality degrades.
- Loading agents "just in case."

## Output

Loading plan as one table: selected agents + skills, token costs, estimated
total, and utilization percent against the 40% ceiling. No narration.
