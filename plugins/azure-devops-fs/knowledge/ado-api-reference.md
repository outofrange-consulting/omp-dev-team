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
| `pr_abandon` | PATCH `…/pullRequests/{id}` `{status:"abandoned"}` |
| `work_item` | GET `/{project}/_apis/wit/workitems/{id}?$expand=all`; create POST `…/workitems/${type}` (json-patch) |
| `search_code` | POST `https://almsearch.dev.azure.com/{org}/{project}/_apis/search/codesearchresults` |
| `pipeline_watch` | GET `/{project}/_apis/build/builds/{buildId}` (poll) |

Self identity (for `pr_vote`): GET `/{org}/_apis/connectionData` → `authenticatedUser.id`.

Vote values: `10` approve, `5` approve with suggestions, `0` reset, `-5` waiting
for author, `-10` rejected.

Refs: <https://learn.microsoft.com/en-us/rest/api/azure/devops/git/>
