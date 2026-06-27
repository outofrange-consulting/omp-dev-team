---
name: semantic-scan
description: Build a computation register and detect semantic duplicates across architectural layers — the same domain calculation reimplemented in domain services, client adapters, and presentation. Runs incrementally (git-diff-based) after the first scan. Use to find logical duplication linters miss.
model: claude-haiku-4.5
metadata:
  tier: small
---

# semantic-scan — detect cross-layer semantic duplicates

Worker pass: detect and report duplicates; do not refactor.

## Constraints

1. Detect and report duplicates; **do not refactor**.
2. Run incrementally (git-diff based) after the first scan.
3. **Be concise.** Report the duplicate table with file:line refs, no narration.

## Steps

### 1. Parse arguments

Capture the optional path and flags.

### 2. Run the scan

Apply the full process from `~/.copilot/dev-team/knowledge/skills/semantic-duplication-scan/SKILL.md` — read that file and follow its process flow, pre-filter rules, annotation procedure, clustering strategy, and report format. This is sequential work in one agent; do not spawn parallel scanners.

### 3. Report

Output the duplicate report.

## Flags

- `[path]` — optional subdirectory to scope the scan. Only files under this path are re-annotated; out-of-scope register entries are preserved.
- `--full` — force full-scan mode regardless of whether a register exists. Bypasses the shallow-clone pre-flight check. Use when `lastScanCommit` is stale or after a major restructuring.
- `--no-opus` — skip the deeper canonical-resolution tier for ambiguous clusters (use `/model` to keep a cheaper tier). Ambiguous clusters are reported as `canonical: ambiguous — human review required`. Use in cost-sensitive environments (CI, personal accounts).
