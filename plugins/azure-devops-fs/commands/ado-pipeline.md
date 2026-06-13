# /ado-pipeline — watch an Azure DevOps build/pipeline

Arguments: `$ARGUMENTS` (a build id).

Run `ado op=pipeline_watch buildId=<id>` and report the final status/result.
Polls every 3s, caps at 20 minutes. `read skill://azure-devops-fs` for context.
