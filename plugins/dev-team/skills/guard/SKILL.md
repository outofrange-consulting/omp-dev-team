---
name: guard
description: >-
  Turn on both safety modes at once for a production-critical session: careful
  mode (destructive commands blocked) plus a freeze lock on the path glob(s) you
  name. Composition only — the careful-mode, destructive-guard and freeze-guard
  extensions do the work.
argument-hint: "<glob> [glob...] | off"
user-invocable: true
allowed-tools: read
---

# Guard

`guard` is a **composition, not a mechanism**. It adds no blocking behaviour of
its own: it runs, in one step, the two commands the extensions already register.

| you ask for | it runs | enforced by |
|---|---|---|
| `guard <glob> [glob...]` | `/careful on`, then `/freeze <glob> [glob...]` | `careful-mode` + `destructive-guard`; `freeze-guard` |
| `guard off` | `/careful off`, then `/unfreeze all` | same |

## Semantics changed — read this before using it

`/freeze <glob>` is a **denylist**: the globs you pass are the paths that become
**un-editable**. The Claude-Code-era `/guard <pattern>` was the inverse — an
allowlist that locked everything *except* the pattern. `freeze-guard` has no
allowlist mode, so name the paths you want **protected**, not the ones you want
to work in.

- `guard src/generated/** migrations/**` — careful mode on; those two trees
  locked; everything else still editable.
- `guard off` — lift both.

## Steps

1. No argument → print the usage table above and stop. Argument `off` → run
   `/careful off` and `/unfreeze all`, confirm both, stop.
2. Run `/careful on`. It reports `careful mode ON — destructive commands will be
   blocked`. (`on` is required: a bare `/careful` only prints status.)
3. Run `/freeze <glob> [glob...]`. It echoes the full frozen set.
4. Confirm in two lines — destructive commands BLOCKED, and the frozen globs.

Write no state file. Both commands persist their own state out of tree at
`~/.omp/state/dev-team/<repoId>/careful.json` and `…/freeze.json` — deliberately
outside the working tree, so the constrained agent cannot lift its own lock with
a file edit.

## Notes

- Full detail lives with each half: the `careful` skill (DENY vs WARN tiers, the
  build-artifact allowlist) and the `freeze` skill (glob syntax, plus the
  best-effort bash branch that also catches `>`/`tee`/`sed -i`/`cp`/`mv` into a
  frozen path).
- Both guards are advisory-grade — regex matching over normalized text, not a
  shell parse, and not a security boundary.
- Supersedes the Claude-Code-era flow that hand-wrote `hooks/careful-state.json`
  and `hooks/freeze-state.json` (the latter with an `allowed_patterns`
  allowlist). Neither file — nor a `hooks/` directory — exists in this repo, so
  that flow enabled nothing at all.
