---
description: Infrastructure/IaC/CI files in scope — secrets, pinning, and supply-chain guardrails
globs:
  - "**/Dockerfile*"
  - "**/*.tf"
  - "**/*.tfvars"
  - "**/*.bicep"
  - "**/docker-compose*.y*ml"
  - "**/.github/workflows/*.y*ml"
---

**An infrastructure / IaC / CI file is in scope.** Path-scoped: this rule loads
only when such a file is being read or edited. Stack-agnostic guardrails:

- **No secrets in IaC or CI.** Reference a secret store / CI secret; never
  hardcode tokens, keys, or connection strings. `.tfvars` holding secrets stay
  out of version control.
- **Pin versions.** Base images by digest or fixed tag (not `latest`);
  actions/modules by pinned ref. Unpinned = an unreviewed supply-chain change
  every run.
- **Least privilege.** Scope IAM/roles and CI tokens to exactly what the step
  needs; default-deny.
- **Fetch-and-execute is a risk.** `curl | bash` without a checksum is an RCE
  vector — pin and verify, or document the accepted risk.
