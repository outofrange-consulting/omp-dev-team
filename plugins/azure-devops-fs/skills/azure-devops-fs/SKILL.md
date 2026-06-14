---
name: azure-devops-fs
description: >-
  Browse and act on Azure DevOps repos and pull requests through the `ado` tool
  and ado:// URIs. Use when the user references an Azure DevOps repo, PR,
  pipeline, or work item, or pastes a dev.azure.com URL.
---

# Azure DevOps as a filesystem

The `ado` tool exposes Azure DevOps the way OMP exposes GitHub via `pr://` /
`issue://`: paths and refs are first-class, reads are cached, mutations are
explicit.

## URI sugar

- `ado://{org}/{project}/{repo}/{path}@{ref}` — a file or tree
- `adopr://{org}/{project}/{repo}/{id}` — a pull request
- `adopr://{org}/{project}/{repo}/{id}/diff[/path]` — PR diff (all / one file)

`org`/`project` default from `AZURE_DEVOPS_ORG` / `AZURE_DEVOPS_PROJECT`, so you
can write `ado://myrepo/src/app.ts@main`. Pass `uri:` to any read op, or pass the
discrete fields (`repo`, `path`, `ref`, `id`).

## Ops

**Read** (cached ~120s): `repo_view`, `repo_ls` (tree), `repo_read` (file),
`pr_view` (threads + merge status + required reviewers + linked work items),
`pr_list`, `pr_files`, `pr_diff`, `work_item`, `search_code`.

**Gates / CI** (Azure specifics):

- `pr_checks` — the merge gate picture: branch-policy **evaluations** (required
  reviewers, min approvals, build validation, comment resolution, merge strategy),
  external **PR statuses**, associated **build-validation runs**, and `mergeStatus`
  (conflicts). The ADO equivalent of GitHub's required checks/reviews.
- `pipeline_list` — list build pipelines/definitions.
- `build_list` — runs (filter by `ref` branch, `status`, `definitionId`).
- `build_logs` — tail the logs of `buildId`.
- `build_run` — queue a build (`definitionId` [+ `ref`]); needs confirmation.
- `pipeline_watch` — poll a running `buildId` to completion.

**Write**: `pr_create` (title/source/target/description/draft), `pr_checkout`
(clones the PR source branch under `~/.omp/wt/...`), `pr_push`, `pr_comment`
(new thread or reply via `threadId`), `pr_vote` (approve / approve-suggestions /
reset / waiting / reject), `pr_complete` (merge now or set auto-complete;
`mergeStrategy` squash|rebase|rebaseMerge|noFastForward), `pr_abandon`,
`work_item` create (`title` + `type`).

## Pagination

`pr_files` / `pr_diff` page the PR iteration changes ($top/$skip) so large PRs are
never truncated; `pr_diff` shows 25 files per call — pass `skip=25`, `skip=50`, …
for the next pages (it prints the next `skip`). Build/pipeline lists follow Azure
continuation tokens. Binary files in a diff are detected and skipped.

## Examples

```
ado op=repo_ls  uri=ado://myrepo/src@main
ado op=repo_read uri=ado://myrepo/src/index.ts@main
ado op=pr_view  uri=adopr://myrepo/4213
ado op=pr_diff  uri=adopr://myrepo/4213/diff/src/index.ts
ado op=pr_list  repo=myrepo status=active
ado op=pr_create repo=myrepo title="Fix X" source=feature/x target=main draft=true
ado op=pr_checkout repo=myrepo id=4213
ado op=pr_comment repo=myrepo id=4213 comment="LGTM, one nit on line 12"
ado op=pr_vote  repo=myrepo id=4213 vote=approve
ado op=pr_checks repo=myrepo id=4213            # gates: policies + statuses + builds
ado op=pr_diff  repo=myrepo id=4213 skip=25      # next page of a large diff
ado op=build_list repo=myrepo ref=main status=completed
ado op=build_logs buildId=88123
ado op=pr_complete repo=myrepo id=4213 mergeStrategy=squash      # merge (confirm)
ado op=pr_complete repo=myrepo id=4213 autoComplete=true         # merge when green
```

## Setup

Set `AZURE_DEVOPS_PAT` (Code R/W, PR R/W, **Build R** for CI, **Policy R** for
`pr_checks` gates), `AZURE_DEVOPS_ORG`, and optionally `AZURE_DEVOPS_PROJECT`.
Side-effecting ops (`pr_abandon`, `pr_complete`, `build_run`, `pr_vote reject`,
force push) prompt for confirmation, or require `confirm: true` when headless.

Reads are cached in `~/.omp/cache/ado-cache.db` (disable with `OMP_ADO_CACHE=0`).
