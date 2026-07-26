---
name: careful
description: >-
  Toggle careful mode: while it is ON, destructive-but-recoverable commands
  (rm -rf on a path, git push --force, git reset --hard, DROP/TRUNCATE, SQL
  DELETE/UPDATE without WHERE, dotnet ef database drop, …) are BLOCKED instead
  of merely warned about. Implemented by the careful-mode extension and
  enforced by destructive-guard.
argument-hint: "on | off | status"
user-invocable: true
allowed-tools: read
---

# Careful

`/careful on|off|status` toggles careful mode. The **`careful-mode` extension**
owns this command end to end and the **`destructive-guard` extension** enforces
it — there is no state file to write by hand.

## Usage

- `/careful on` — block destructive-but-recoverable commands.
- `/careful off` — back to warn-only.
- `/careful status` — report the current mode. **Any argument other than `on` or
  `off` — including no argument at all — reports status; it does not enable.**
  Say `on` explicitly.

## How it works (reference)

- **State** is `{ "active": bool, "since"?: ISO }`, persisted **out of tree** at
  `~/.omp/state/dev-team/<repoId>/careful.json` (`<repoId>` = sha256 of the git
  root, first 16 hex; override the directory with `OMP_DEVTEAM_STATE_DIR`). Same
  location and rationale as the freeze lock: outside the working tree, so the
  constrained agent cannot flip its own guard off with a file edit. A legacy
  in-tree `.omp/state/` path is still read as a fallback.
- **Enforcement** is `destructive-guard`'s `tool_call` hook on `bash`. It splits
  the command line on `&&`, `||`, `;`, `|` and newlines and evaluates each
  segment independently, so a safe segment can never launder a dangerous sibling.
- You do **not** write any state file yourself; running the command does it.

## Two tiers — this toggle controls only the second one

| tier | examples | careful OFF | careful ON |
|---|---|---|---|
| **DENY** — catastrophic, unrecoverable | fork bombs; recursive `rm` of `/`, `/*`, `~`, `$HOME`; any `rm --no-preserve-root` | **blocked** | **blocked** |
| **WARN/CAREFUL** — destructive, recoverable | `rm -rf <path>`, `find … -delete`, `shred`, `truncate -s 0`, `git push --force`, `git reset --hard`, `git clean -fd`, `git branch -D`, `git checkout -- .`, `DROP TABLE/DATABASE/SCHEMA/VIEW/INDEX`, `TRUNCATE TABLE`, `dotnet ef database drop`, SQL `DELETE`/`UPDATE` with no `WHERE` in the same segment, `kill -9`/`killall`/`pkill`, `chmod 777`, `mkfs`/`dd if=`/`> /dev/sd*` | warning only | **blocked** |

The DENY tier is deliberately **not** overridable in-agent — not even by
`/careful off`. If a root/home wipe is genuinely intended, the human runs it
outside the agent.

A short allowlist short-circuits the WARN tier for the usual build-artifact
wipes (`node_modules`, `dist`, `build`, `.cache`, `coverage`, `tmp`,
`__pycache__`, `.next`, `target/debug`, and subpaths under them). A segment
qualifies only if `rm` is its *operative* command, with exactly one target and
only recursive/force flags — so `rm -rf dist && rm -rf /etc` still trips on the
second segment.

## Notes

- Detection is **advisory-grade**: `destructive-guard` matches normalized text
  with regexes, it does not parse the shell. It catches obvious dangerous forms;
  it is not a bypass-proof sandbox (see the operating manual).
- Pair with `/freeze <glob>` to lock a path surface too, or use the `guard` skill
  to turn both on in one step.
- Supersedes the Claude-Code-era flow that hand-wrote `hooks/careful-state.json`
  and read `hooks/destructive-commands.json` through a `destructive-guard.sh`
  hook. None of those paths exist in this repo — that flow silently never
  activated careful mode, which is why this skill now documents the command
  instead of instructing you to write state. The pattern set lives **in code** in
  the extension, so it is described here rather than pointed at as a JSON file
  the guard would have to be trusted to re-read.
