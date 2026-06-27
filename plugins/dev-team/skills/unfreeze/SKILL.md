---
name: unfreeze
description: >-
  Lift a scope lock set by /freeze. Implemented by the freeze-guard extension.
argument-hint: "<glob> | all"
user-invocable: true
allowed-tools: read
---

# Unfreeze

`/unfreeze <glob>` removes specific glob(s) from the freeze set; `/unfreeze all`
(or no arguments) clears every lock. The **`freeze-guard` extension** owns this —
there is no state file to delete by hand.

## Usage

- `/unfreeze all` — clear all locks.
- `/unfreeze src/auth/**` — unlock just that glob (space-separated for several).

## How it works (reference)

The command updates the same out-of-tree state `/freeze` writes —
`~/.omp/state/dev-team/<repoId>/freeze.json` (`{ "globs": [...] }`,
`OMP_DEVTEAM_STATE_DIR` to relocate). Removing a glob (or `all`) lets the
extension's `tool_call` guard stop blocking edits to those paths.

## Notes

- Supersedes the earlier Claude-Code-era flow that did `rm hooks/freeze-state.json`
  — that path is not how freeze state is stored in this repo.
