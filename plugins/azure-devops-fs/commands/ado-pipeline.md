# /ado-pipeline — Azure DevOps builds & pipelines

Arguments: `$ARGUMENTS` (a build id to watch, or blank to browse).

- Watch a run: `ado op=pipeline_watch buildId=<id>` (polls 3s, caps 20 min) and
  report the final status/result.
- Browse: `ado op=pipeline_list` (definitions), `ado op=build_list ref=<branch>
  status=completed` (recent runs), `ado op=build_logs buildId=<id>` (tail logs).
- Trigger: `ado op=build_run definitionId=<id> ref=<branch>` (asks confirmation).

`read skill://azure-devops-fs` for context.
