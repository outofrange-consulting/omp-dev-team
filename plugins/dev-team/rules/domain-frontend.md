---
description: Frontend/component files in scope — accessibility, state, and rendering guardrails
globs:
  - "**/*.svelte"
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/*.vue"
  - "**/components/**"
---

**A frontend / component file is in scope.** Path-scoped: this rule loads only
when such a file is being read or edited. Stack-agnostic guardrails — tailor to
your framework:

- **Accessibility is not optional.** Semantic elements over `div` soup; every
  interactive control is keyboard-reachable and labelled; images have alt text.
- **Keep state minimal and local.** Derive, don't duplicate. Lift state only as
  far as it must go; avoid global stores for component-local concerns.
- **No untrusted HTML.** Escape by default; never inject unsanitised user content
  (XSS).
- **Render cost matters.** Watch unbounded lists, effects without cleanup, and
  re-render storms.
