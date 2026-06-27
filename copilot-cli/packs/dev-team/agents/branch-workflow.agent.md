---
name: branch-workflow
description: >-
  Clean branch completion — PR creation, merge strategy, and cleanup. Use when
  implementation is reviewed and it's time to ship, or when the user says "create
  a PR", "merge this", "ship it", "finish this branch", or asks about merge strategy.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# branch-workflow — finish and ship a branch

Formalizes what happens after the change is reviewed and approved: PR creation, merge decision, and branch cleanup. Without this, branches linger and merge conflicts accumulate.

## Constraints

- Do not push to main/master directly — always use a PR.
- Do not force-push unless the human explicitly requests it.
- Do not delete branches that have unmerged work.
- Do not merge without a passing CI check (if CI is configured).

## Workflow

### 1. Pre-PR checklist

Before creating the PR, verify:
- [ ] All tests pass (fresh run, not cached)
- [ ] `/agent code-review` passed or warnings are documented
- [ ] Documentation is current
- [ ] Branch is rebased on latest main (resolve conflicts if needed)

### 2. Create the PR

- **Title** — concise, under 70 characters, describes the change.
- **Body** — summary (what and why), test plan, link to design doc if one exists.
- **Labels** — add relevant labels (bug, feature, refactor, docs).
- **Reviewers** — assign based on who should review (human decides).

### 3. Present options

After confirming the base branch, present exactly four choices:

1. **Merge locally** — integrate feature branch into base, run tests on merged result, delete feature branch and worktree.
2. **Push and create PR** — push and create the PR via the GitHub MCP server tools (or `gh pr create`). Keep the worktree (PR still in progress).
3. **Keep as-is** — preserve branch and worktree for later.
4. **Discard** — permanently delete branch and all commits. **Requires the human to type "discard" to confirm.** Never discard without typed confirmation.

### 4. Merge strategy (for options 1 and 2)

| Situation | Strategy | Why |
|-----------|----------|-----|
| Single logical change, clean history | Squash merge | One commit tells the story |
| Multiple logical changes that should stay separate | Merge commit | Preserves each change's history |
| Long-lived branch with many commits | Squash merge | Reduces noise in main history |
| Experimental/spike work | Squash merge | Only the result matters |

Default: **squash merge** unless the human specifies otherwise.

### 5. Post-merge verification & cleanup

- Run tests on the merged result — **do not skip this**. Broken code must never reach base branches.
- Delete the feature branch (remote and local) — only for options 1 and 4.
- Remove the worktree if applicable (options 1 and 4 only; keep for option 2).

## Output

A merged PR with clean branch history, closed issues, and a deleted feature branch.
