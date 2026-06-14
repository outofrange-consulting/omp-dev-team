# Azure DevOps REST mapping (api-version 7.1)

How each `ado` op maps to the REST API. Base: `https://dev.azure.com/{org}`,
project base `…/{org}/{project}`. Auth: `Authorization: Basic base64(":"+PAT)`.

| op | method + endpoint |
|---|---|
| `repo_view` | GET `/{project}/_apis/git/repositories/{repo}` |
| `repo_ls` | GET `…/repositories/{repo}/items?scopePath=&recursionLevel=OneLevel&versionDescriptor.*` |
| `repo_read` | GET `…/repositories/{repo}/items?path=&includeContent=true&versionDescriptor.*` → `.content` |
| `pr_view` | GET `…/repositories/{repo}/pullRequests/{id}` (+ `/threads`) |
| `pr_list` | GET `…/repositories/{repo}/pullRequests?searchCriteria.status=&$top=` |
| `pr_files` | GET `…/pullRequests/{id}/iterations` → last → `/iterations/{n}/changes` |
| `pr_diff` | iterations changes + GET items at base/source commit, then `git diff --no-index` |
| `pr_create` | POST `…/repositories/{repo}/pullRequests` `{sourceRefName,targetRefName,title,description,isDraft}` |
| `pr_checkout` | git clone `--single-branch --branch <src>` of `…/_git/{repo}` (auth via http.extraheader) |
| `pr_push` | git push `HEAD:refs/heads/<src>` from the worktree |
| `pr_comment` | POST `…/pullRequests/{id}/threads` (new) or `…/threads/{tid}/comments` (reply) |
| `pr_vote` | PATCH `…/pullRequests/{id}/reviewers/{selfId}` `{vote: 10/5/0/-5/-10}` |
| `pr_complete` | PATCH `…/pullRequests/{id}` `{status:"completed", lastMergeSourceCommit, completionOptions:{mergeStrategy}}` — or `{autoCompleteSetBy:{id:self}, completionOptions}` for auto-complete |
| `pr_abandon` | PATCH `…/pullRequests/{id}` `{status:"abandoned"}` |
| `pr_checks` | PR `mergeStatus` + GET `/{project}/_apis/policy/evaluations?artifactId=vstfs:///CodeReview/CodeReviewId/{projectGuid}/{prId}` + GET `…/pullRequests/{id}/statuses` + GET `/{project}/_apis/build/builds?branchName=refs/pull/{id}/merge` |
| `pipeline_list` | GET `/{project}/_apis/build/definitions` (continuation-token paged) |
| `build_list` | GET `/{project}/_apis/build/builds?branchName=&statusFilter=&definitions=` (continuation-token paged) |
| `build_logs` | GET `…/build/builds/{buildId}/logs` → last → GET `…/logs/{logId}` (raw, tailed) |
| `build_run` | POST `/{project}/_apis/build/builds` `{definition:{id}, sourceBranch}` |
| `work_item` | GET `/{project}/_apis/wit/workitems/{id}?$expand=all`; create POST `…/workitems/${type}` (json-patch) |
| `search_code` | POST `https://almsearch.dev.azure.com/{org}/{project}/_apis/search/codesearchresults` |
| `pipeline_watch` | GET `/{project}/_apis/build/builds/{buildId}` (poll) |

Self identity (for `pr_vote`/`pr_complete`): GET `/{org}/_apis/connectionData` → `authenticatedUser.id`.

Vote values: `10` approve, `5` approve with suggestions, `0` reset, `-5` waiting
for author, `-10` rejected.

## Azure specifics & pagination

- **PR iteration changes** (`pr_files`/`pr_diff`) are paged with `$top`/`$skip`
  (1000/page, cap 5000) so large PRs are not truncated. `pr_diff` renders 25 files
  per call; pass `skip=25/50/…` for more (it prints the next `skip`). Binary blobs
  (NUL-detected) are skipped, not diffed.
- **Continuation tokens**: list endpoints (builds, definitions) return
  `x-ms-continuationtoken`; the client loops it via `listToken`. PR lists page via
  `$skip`.
- **Gates** = branch **policy evaluations** (required reviewers, min approvals,
  build validation, comment resolution, merge strategy). `pr_checks` joins them
  with external PR **statuses**, the PR-merge **build runs**, and `mergeStatus`
  (conflicts). Policy reads need the **project GUID** (via `/_apis/projects/{name}`)
  and a PAT with **Policy (read)**; build reads need **Build (read)**.
- **Merge strategies** for `pr_complete`: `squash`, `rebase`, `rebaseMerge`,
  `noFastForward`.

Refs: <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/>
· policy: <https://learn.microsoft.com/en-us/rest/api/azure/devops/policy/evaluations>
· build: <https://learn.microsoft.com/en-us/rest/api/azure/devops/build/builds>
