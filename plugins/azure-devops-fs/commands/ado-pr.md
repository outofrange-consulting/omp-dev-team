# /ado-pr — view or create an Azure DevOps pull request

Arguments: `$ARGUMENTS`
- a PR id / `adopr://…` URI → **view** it (`ado op=pr_view`), then offer the diff
  (`ado op=pr_diff`).
- `create` (or flags like `--source --target --title`) → **create** a PR
  (`ado op=pr_create`). Confirm source/target/title before creating.

`read skill://azure-devops-fs` first. Write the PR summary to chat; write any
generated description to a file if long.
