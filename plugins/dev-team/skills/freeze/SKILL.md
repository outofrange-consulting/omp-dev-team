---
name: freeze
description: >-
  Scope-lock file editing to glob pattern(s): only files matching a frozen glob
  are blocked from edits until /unfreeze. Implemented and enforced by the
  freeze-guard extension.
argument-hint: "<glob> [glob...]"
user-invocable: true
allowed-tools: read
---

# Freeze

`/freeze <glob> [glob...]` locks the given path globs against edits. The
**`freeze-guard` extension** owns this command end to end — there is no state
file to write by hand.

## Usage

- `/freeze src/auth/**` — lock everything under `src/auth/`.
- `/freeze src/auth/** src/middleware/**` — multiple globs (space-separated).
- `/freeze` with no arguments — print the currently frozen globs.

## How it works (reference)

- **State** is `{ "globs": [...] }`, persisted **out of tree** at
  `~/.omp/state/dev-team/<repoId>/freeze.json` (`<repoId>` = sha256 of the git
  root, first 16 hex; override the directory with `OMP_DEVTEAM_STATE_DIR`). It is
  deliberately outside the working tree so the constrained agent cannot rewrite
  its own lock. A legacy in-tree `.omp/state/` path is still read as a fallback.
- **Enforcement** is the extension's `tool_call` hook: a `write`/`edit` — or a
  shell write via redirection / `tee` / `sed -i` / `cp`/`mv` destination — to a
  frozen path is **blocked**, with a message naming the matching glob and how to
  lift it.
- You do **not** write any state file yourself; running the command does it.

## Notes

- Lift with `/unfreeze <glob>` or `/unfreeze all`.
- State lives on disk, so it persists across tool calls and sessions; if a
  session ends while frozen, run `/unfreeze all` in the next session to clear it.
- Supersedes the earlier Claude-Code-era flow that hand-wrote
  `hooks/freeze-state.json` and relied on a `pre-tool-guard.sh` hook — neither
  exists in this repo.
