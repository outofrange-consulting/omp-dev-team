<!-- dev-team:begin -->
# Dev-team operating manual (GitHub Copilot CLI)

This repository runs the **dev-team** discipline ported to Copilot CLI. A
`preToolUse` hook enforces the pipeline; the `dt` CLI drives the gate; custom
agents (`/agent orchestrator|specs|plan|build|review|pr` and the critics) run
each phase. Follow this manual on every non-trivial change.

## The enforced pipeline: scope → plan → build → review → pr

Editing production **source** is blocked until the task is scoped and (if
non-trivial) a plan is approved; `git commit` is blocked until the staged set is
review-approved. This binds both the agent and the human.

1. **Scope** — `dt scope` (or `dt scope --trivial` for a typo/one-liner, or
   `dt scope --complex`). Classify from objective signals; when unsure, scope up.
2. **Specs** (behavior changes) — write Gherkin `.feature` acceptance criteria
   (`/agent specs`). Existing specs are write-protected — fix code, not the test.
3. **Plan** — `/agent plan`. The plan is the review artifact. Human signs off,
   then runs `dt plan-approve`. **When asked for a plan, produce only the plan** —
   do not start implementing.
4. **Build** — `/agent build`. Implement the plan; tests required (test-after is
   fine, test-first is not); refactor after green.
5. **Review** — `/agent review` + critics. Human runs `dt review-approve`, then
   commit.
6. **PR** — `/agent pr`. Feature branch, body mirrors the plan + verification.

`dt status` shows the gate; `dt reset` re-arms it for the next task.

## Tests

Every behavior change ships with tests. A unit is **not done** until its tests
exist and pass — verified by **running them**, not from memory. Never edit a
failing test (or weaken/skip/delete one) to go green; fix the code. Match the
existing framework and style.

## Quality bar

- Smallest correct change; resist scope creep — flag adjacent issues, don't
  silently fix them.
- Clear names over comments; small cohesive functions; remove duplication.
- Use the platform/stdlib instead of reinventing it; YAGNI over speculative
  generality.
- Never disable analyzers/linters or weaken types to pass — fix the root cause.
- Don't write secrets (`.env`, `*.pem`, `*.key`, `*secret*`) — the path-guard
  blocks it. Don't edit frozen paths (`dt status`) without `dt unfreeze`.

## Output discipline

Write deliverables (plans, designs, code, reports) to **files**, not chat. No
"I will…" preamble — state results directly and end with one sentence: what
changed and what's next. Report verification faithfully: if tests fail, say so
with the output; if a step was skipped, say that.

## Knowledge corpus & agents

The full dev-team reference library is installed at
`~/.copilot/dev-team/knowledge/` (skills, rules, prompts, and the
`dev-team-knowledge` corpus: review rubrics, the test-pyramid/quadrants, OWASP
detection, testing techniques, model-routing, schemas). Consult it when a task
needs that depth — read the specific file, don't reload the whole tree.

Specialist and critic agents are available via `/agent <name>` — e.g.
`security-review`, `domain-review`, `arch-review`, `performance-review`,
`test-review`, `structure-review`, `naming-review`, `qa-engineer`,
`tech-writer`, plus capability agents (`threat-modeling`, `systematic-debugging`,
`docker-image-audit`, `mutation-testing`, `domain-driven-design`, …). Route by
what changed (see the `orchestrator` agent's table).

## The guards are advisory

The guards are out-of-tree, advisory-grade enforcement — rails, not a sandbox.
Treat a block as "do the missing step", not an obstacle to route around. Don't
`commit --no-verify` to dodge review unless the human explicitly asks.
<!-- dev-team:end -->
