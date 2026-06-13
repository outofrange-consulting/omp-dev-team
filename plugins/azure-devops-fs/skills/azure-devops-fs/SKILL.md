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
`pr_view` (with threads), `pr_list`, `pr_files`, `pr_diff`, `work_item`,
`search_code`.

**Write**: `pr_create` (title/source/target/description/draft), `pr_checkout`
(clones the PR source branch under `~/.omp/wt/...`), `pr_push`, `pr_comment`
(new thread or reply via `threadId`), `pr_vote` (approve / approve-suggestions /
reset / waiting / reject), `pr_abandon`, `pipeline_watch` (poll a build),
`work_item` create (`title` + `type`).

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
```

## Setup

Set `AZURE_DEVOPS_PAT` (Code R/W, PR R/W), `AZURE_DEVOPS_ORG`, and optionally
`AZURE_DEVOPS_PROJECT`. Destructive ops (`pr_abandon`, `pr_vote reject`, force
push) prompt for confirmation, or require `confirm: true` when headless.

Reads are cached in `~/.omp/cache/ado-cache.db` (disable with `OMP_ADO_CACHE=0`).
