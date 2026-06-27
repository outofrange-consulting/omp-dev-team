---
name: issues-from-plan
description: >-
  Break an implementation plan into independently-grabbable GitHub issues with
  preserved ordering and dependency links. Use when the user says "create issues
  from this plan", "break this into tickets", "file issues", or wants to
  distribute plan steps across a team.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# issues-from-plan — decompose a plan into GitHub issues

Break an implementation plan into GitHub issues that can be worked independently. Decompose the plan; do not implement. Preserve plan ordering and dependencies as issue links. Be concise — report created issue numbers, no narration.

## Process

### 1. Find the plan

If a path is provided, read that file. Otherwise look for the most recent plan in the active conversation context, the `memory/` directory (phase progress files), or a `plans/` directory. If no plan is found, ask the user to point you to one.

### 2. Analyze the plan

Identify each discrete unit of work (implementation step, vertical slice, or phase), the dependencies between units (which must complete before others can start), the acceptance criteria for each unit, and the shared architectural decisions that apply across all issues.

### 3. Draft issues

For each unit, draft an issue with:

- **Title** — short, action-oriented (e.g., "Add user authentication endpoint").
- **Body** — what to build (behavior, not implementation), acceptance criteria as checkboxes, dependencies on other issues (by title reference), relevant architectural decisions from the plan, and the testing approach.
- **Labels** — suggest appropriate labels if the repo uses them.

### 4. Review with the user

Present the issue list as a numbered summary:

```
1. [Title] — [one-line description] (depends on: none)
2. [Title] — [one-line description] (depends on: #1)
3. [Title] — [one-line description] (depends on: #1)
```

Ask: "Does this breakdown look right? Should any issues be merged or split?" Wait for approval before creating.

### 5. Create issues

Create each issue with the GitHub MCP server tools (or `gh issue create` if available). After creating all issues, update bodies to cross-reference the actual issue numbers for dependencies.

```bash
gh issue create --title "Issue title" --body "$(cat <<'EOF'
## What to Build

[Behavior description — what this slice delivers end-to-end]

## Depends On

- #<number>: [brief reason]

## Acceptance Criteria

- [ ] Criterion 1
- [ ] Criterion 2
- [ ] All tests pass

## Architectural Context

[Relevant decisions from the plan that apply to this issue]

## Testing Approach

[What to test and how — behavior-level, not implementation-level]
EOF
)"
```

### 6. Present results

List all created issue URLs with their titles. Note the dependency graph.
