# /ado — Azure DevOps as a filesystem

`read skill://azure-devops-fs` for the full op list and URI scheme, then carry
out the request in `$ARGUMENTS` using the `ado` tool.

Quick map:
- **Read**: `ado op=repo_ls|repo_read|pr_view|pr_list|pr_files|pr_diff|work_item|search_code` (accepts `uri=ado://…` / `adopr://…`)
- **Write**: `ado op=pr_create|pr_checkout|pr_push|pr_comment|pr_vote|pr_abandon|pipeline_watch`

Needs `AZURE_DEVOPS_PAT` (+ `AZURE_DEVOPS_ORG`, optional `AZURE_DEVOPS_PROJECT`).
