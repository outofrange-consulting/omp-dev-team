---
description: Approve the current plan and unlock the build phase (clears the plan gate).
allowed-tools:
  - Bash
---

The human has reviewed and signed off on the plan. Clear the plan gate so the build phase can edit production source:

```
devteam-gate plan-approve
```

Confirm the gate is cleared and that `/build` can now proceed.
