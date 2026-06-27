# /pr — run quality gates and open a pull request

Role: **orchestrator**. Final phase of the pipeline.

Arguments: `$ARGUMENTS` (optional PR title / target branch).

## Run it

1. `read skill://pr` and follow it exactly.
2. Confirm `/code-review` passed and the review gate is cleared
   (`/review-approve`).
3. Follow `read skill://branch-workflow` for branch creation, merge strategy,
   and cleanup.
4. Open the PR with a body that links the spec, the plan, and the verification
   evidence. Do not push to a protected branch without explicit permission.
