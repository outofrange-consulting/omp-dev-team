---
description: Azure DevOps PAT handling — never print, commit, or hardcode the token
globs:
  - "**/*"
---

**The Azure DevOps PAT is a secret.**

- Read it only from `AZURE_DEVOPS_PAT` (env). Never echo it, write it to a file,
  embed it in a remote URL, or paste it into a commit/PR/comment.
- The `ado` tool injects auth via an in-memory `http.extraheader` — do not switch
  to URL-embedded credentials.
- Scope the PAT to least privilege: Code (Read & Write) and Pull Request
  (Read & Write); add Build (Read) only if you use `pipeline_watch`.
- Treat `pr_abandon`, `pr_vote reject`, and force pushes as destructive — they
  require confirmation (UI prompt, or `confirm: true` when headless).
