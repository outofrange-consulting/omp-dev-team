---
description: Approve the current staged diff and unlock commit (clears the blocking review gate).
allowed-tools:
  - Bash
---

Code review has passed for the **currently staged** changes. Approve them:

```
devteam-gate review-approve
```

This writes a content-hash of `git diff --cached` to `.review-passed` at the repo
root. The review gate is **blocking**: `git commit` is denied until this hash
matches. **Any edit to a staged file after approval invalidates it** — re-stage,
re-run `/code-review`, and `/review-approve` again. A successful commit clears the
approval automatically. `git commit --no-verify` is the logged escape hatch.
