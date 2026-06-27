---
name: azure-devops
description: >-
  Work with Azure DevOps (ADO) from Claude Code via the official @azure-devops/mcp
  server: read repos/files, view and create pull requests, watch pipelines/builds,
  read and update work items, search code, wiki, and test plans. Use whenever the
  user mentions Azure DevOps / ADO, an ADO pull request, a pipeline/build, or a
  work item (User Story / Bug / Task / PBI). NOTE: ADO PRs are NOT GitHub PRs.
---

# Azure DevOps (official MCP)

Azure DevOps is exposed through Microsoft's official MCP server (`@azure-devops/mcp`),
registered by this plugin (`mcp__azure-devops__*` tools). It is authenticated with
the **Azure CLI** (`az login`, `DefaultAzureCredential`) — there is no PAT in config.

## Before you start
- The org comes from this plugin's `userConfig.org` (set on enable). If a tool
  fails with an auth error, the user likely needs to run `az login` (a browser may
  open on the first call), or `az account set --subscription <id>`.
- Use the MCP tools (`mcp__azure-devops__*`); discover them with the tool list.
  Common domains: **core/projects**, **repositories**, **pull_requests**, **work
  items**, **pipelines/builds**, **search**, **wiki**, **test plans**.

## Typical flows
- **Review a PR**: list/﻿view the PR, fetch its diff/threads, read the changed
  files, then add a comment or vote via the PR tools.
- **Work items**: query by id or WIQL, read fields/links, update state or add a
  comment. Ground every claim in the item's actual fields (don't invent status).
- **Pipelines**: list definitions/builds, read build logs, trigger a run (treat a
  run trigger as a mutation — confirm with the user first).

## Local git actions
PR **checkout / push** are local-git operations — do them with Claude Code's native
git via Bash (`git fetch`, `git checkout`, `git push`), not the MCP. The MCP is for
the ADO REST surface (PR metadata, comments, votes, pipelines, work items).

## Safety
Treat `pr_abandon`, reject votes, force pushes, and build triggers as **destructive
— confirm with the user first**. Never echo or commit credentials; auth is the
ambient `az` session, so nothing secret should appear in commands or output.
