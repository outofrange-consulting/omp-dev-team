---
name: pr
description: >-
  Open a pull request once the change is reviewed and committed. Writes a PR body
  that mirrors the plan and the verification evidence, on a feature branch.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# pr — ship the reviewed change

Create the pull request after the change is committed (the commit required
`dt review-approve`). Never push directly to the default branch.

## Steps

1. **Branch.** If on the default branch, create a feature branch first
   (`<type>/<short-slug>`), then push with upstream tracking.
2. **Commit hygiene.** Ensure commits are coherent and messages explain the *why*.
3. **Open the PR.** Prefer the GitHub MCP server tools (or `gh` if available).
   Check for a PR template (`.github/pull_request_template.md` and the usual
   locations); if present, mirror its section headings and fill them from the
   change — skip any section asking for secrets/tokens/internal hostnames.
4. **Body.** Summarize: the problem, the approach (from the plan), the file-level
   changes, the test strategy, and the **verification evidence** (the exact
   commands run and their results). Link the spec/plan if they live in the repo.

## Guardrails

- Don't fabricate test results — report what actually ran.
- Don't open a PR if review found unresolved error-severity issues.
- Ask the human before creating the PR unless they've told you to just ship it.
