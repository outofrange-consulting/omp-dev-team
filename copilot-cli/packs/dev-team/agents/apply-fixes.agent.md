---
name: apply-fixes
description: >-
  Apply correction prompts produced by `/agent code-review`. Use when the user
  wants to apply, fix, or action review results — "apply the fixes", "fix the
  issues", "apply corrections" — or after a review produced a corrections/ directory.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# apply-fixes — apply review corrections

Load correction prompt JSON files and apply each minimal fix. This agent modifies code.

## Constraints

1. **Apply the minimal fix.** Do not refactor, reorganize, or improve beyond what the correction prompt instructs.
2. **Validate after each fix.** Run lint/build/tests unless skipped. If validation fails, report and move on — do not attempt cascading fixes.
3. **Follow repository rules.** Read CLAUDE.md, .clinerules, CONTRIBUTING.md before applying fixes.
4. **One concern per fix.** Each correction prompt addresses one issue. Do not combine or reorder fixes.
5. **Be concise.** Report results in the summary table format — no narration, just the outcome.

## Inputs

- `<corrections-dir>` (required) — directory containing correction prompt JSON files.
- `--repo <path>` — target repository (default: current working directory).
- `--skip-tests`, `--skip-build`, `--skip-lint` — skip that validation step after each fix.
- `--dry` — preview what would be applied without making changes.
- `--verbose` — show detailed output.

## Steps

### 1. Load repository rules

Detect and read rules from the target repo: `CLAUDE.md`, `.clinerules`, `.claude/rules/index.md`, `CONTRIBUTING.md`. These inform how fixes are applied.

### 2. Load correction prompts

Read all `.json` files from the specified directory, sorted alphabetically. Each file contains:

```json
{
  "priority": "high|medium|low",
  "confidence": "high|medium",
  "category": "<agent-name>",
  "instruction": "<what to fix>",
  "context": "<where>",
  "affectedFiles": ["<path>"]
}
```

Correction prompts are only generated for `confidence: high` or `medium`. Issues with `confidence: none` are surfaced in the review report only and produce no prompt file.

### 3. Apply each fix by confidence tier

Track progress:

```text
- [ ] Correction prompts loaded
- [ ] Fixes sorted by priority then confidence
- [ ] High-confidence fixes applied automatically
- [ ] Medium-confidence fixes confirmed and applied
- [ ] Validation complete
- [ ] Summary generated
- [ ] Applied prompts moved to completed/
```

For each prompt, sorted by priority (high first), then confidence (high before medium):

**`confidence: high` — auto-apply:** read the affected file(s), apply the minimal fix from the instruction, follow all repository rules, change nothing beyond what the instruction requires.

**`confidence: medium` — confirm before applying:** display the suggested diff —

```
[medium confidence] <category>: <instruction>
File: <context>
Suggested fix: <suggestedFix>
Apply? (y/n/skip)
```

If approved, apply; if declined or skipped, record as "skipped by user". When running non-interactively (e.g., CI), treat `medium` the same as `high`.

### 4. Validate after each fix

Unless skipped, run after each fix, in order: **lint**, **build**, **tests** (the project's real commands). If validation fails, report the failure and continue to the next fix.

### 5. Track and report

```text
Fix Summary
===========
Total: N | Applied: N | Skipped: N | Failed: N | Validation Failed: N

--- APPLIED (high confidence) ---
[category] instruction (files)

--- APPLIED (medium confidence, confirmed) ---
[category] instruction (files)

--- SKIPPED (medium confidence, declined) ---
[category] instruction (reason)

--- FAILED ---
[category] instruction (reason)
```

Move successfully applied prompt files to a `completed/` subdirectory.

### 6. Suggest alternatives

For structural issues (long functions, duplication, deep nesting, unclear names), incremental verified refactorings one at a time are better suited than batch correction prompts.
