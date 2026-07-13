---
name: scope-control
description: >-
  Limit what the agent may touch this session — careful mode (block destructive
  commands like rm -rf / force-push / DROP TABLE) and freeze/guard (scope-lock
  editing to a glob). Use when the user says "careful mode", "freeze", "unfreeze",
  "guard", "lock editing", "protect production", or wants a safety leash.
---

# Scope control (careful · freeze · guard)

Session safety leashes. **Note for the Claude Code port:** the hard enforcement
lives in two places — careful mode is tracked by the dev-team gate
(`devteam-gate careful on|off`), and destructive-command / secret safety is
enforced by Claude Code's native `permissions` (deny/ask in settings.json). The
`freeze`/`unfreeze`/`guard` glob-locks are **advisory** here (there is no freeze
hook); honor them as working agreements. See `references/` for each mode.
