---
description: Approve the current staged diff and unlock commit (clears the review gate).
allowed-tools:
  - Bash
---

Code review has passed for the **currently staged** changes. Clear the review gate:

```
devteam-gate review-approve
```

This hashes the current `git diff --cached`; if you stage more changes afterwards, re-run `/code-review` and `/review-approve`. Then proceed to commit / `/pr`.
