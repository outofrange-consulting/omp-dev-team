# /ado-review — pull an Azure DevOps PR locally and review it

Role: worker. Standalone — does not require any other plugin.

Arguments: `$ARGUMENTS` (a PR id or `adopr://…` URI).

## Steps

1. `read skill://azure-devops-fs`.
2. `ado op=pr_view` the PR (title, description, threads, merge status) and
   `ado op=pr_diff` for the changes (paginated — pass `skip=25` for more files).
3. `ado op=pr_checks` to see the merge gates — branch policies, required reviewers,
   PR statuses and build-validation runs — so the review accounts for what's
   already blocking/passing (and `ado op=build_logs buildId=<id>` if a build failed).
4. `ado op=pr_checkout` to clone the PR source branch into a local worktree
   (`~/.omp/wt/...`) so you can run tests/tools against real files.
5. Review the diff: correctness, tests, security, clarity. Summarize findings as
   actionable comments.
6. Optionally post them with `ado op=pr_comment` (one thread per finding), and/or
   `ado op=pr_vote vote=approve|waiting`. If approved and gates pass,
   `ado op=pr_complete` (merge now, or `autoComplete=true` to merge once green).

> Synergy (optional): if the **dev-team** plugin is also installed, run
> `/code-review` in the checked-out worktree for the full multi-agent review,
> then bring the findings back here as PR comments. This plugin works fine
> without dev-team.
