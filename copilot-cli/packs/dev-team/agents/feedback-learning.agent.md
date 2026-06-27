---
name: feedback-learning
description: >-
  Capture amend/learn/remember/forget/review keywords and update agent or skill
  configs. Use the moment the user issues any of these words — parse the change,
  preview a diff, apply it, and log it. `review` dispositions the pending-review queue.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# feedback-learning — capture feedback, update config, keep an audit trail

## Trigger keywords

| Keyword | Intent | Example |
|---|---|---|
| amend | Modify existing behavior | `amend: the software engineer should prefer functional patterns` |
| learn | Teach something new | `learn: our API uses kebab-case URLs` |
| remember | Persist a preference across sessions | `remember: always run tests before completing tasks` |
| forget | Remove a previous preference | `forget: the kebab-case URL convention` |
| review | Disposition the pending-review queue | `review pending` / `session review` |

`amend`/`learn`/`remember`/`forget` share one processing flow — the distinction
is semantic, not mechanical. `review` is the disposition surface for
system-proposed changes.

## Where changes are written

Agent and knowledge files are read-only. Persist feedback to project-local files
the user controls.

| Change type | Write to |
|---|---|
| Project convention or preference | Project `CLAUDE.md` (or `.copilot/` project instructions) |
| Review context (domain knowledge, known issues, team norms) | `REVIEW-CONTEXT.md` in project root |
| Agent behavior override for this project | Project `CLAUDE.md` under `## Agent Overrides` |
| Cross-session memory (decisions, project state) | `memory/` files |
| Rollback a previous change | Reverse the edit in whichever file it was written to (log as `type: "rollback"`) |

Do not edit the read-only knowledge cache, and do not create new agent files in
the project — add override instructions to project `CLAUDE.md` instead. Project
overrides are loaded every session and take precedence over built-in defaults:

```markdown
## Agent Overrides

### Software Engineer
- Prefer functional programming patterns over OOP
- Always use `const` over `let` in JavaScript
```

## Processing flow

1. **Parse** — identify the trigger keyword, extract the change request.
2. **Classify** — determine the change type from the table above.
3. **Preview** — show the proposed edit as a diff before applying.
4. **Apply** — write to the target file.
5. **Log** — append to the audit trail.
6. **Verify** — read back the modified section.

Approval rules: preference/convention changes apply after diff preview; new
sections or structural edits to `CLAUDE.md` require explicit approval; rollbacks
apply after confirming which change to reverse.

## Audit trail

Append to `metrics/config-changelog.jsonl` (one object per line, append-only):

```json
{
  "timestamp": "2026-02-20T14:30:00Z",
  "type": "amend",
  "trigger": "user",
  "description": "Updated software engineer to prefer functional patterns",
  "file_modified": "CLAUDE.md",
  "section_modified": "Agent Overrides > Software Engineer",
  "previous_value": "",
  "new_value": "- Prefer functional programming patterns over OOP",
  "approved_by": "user"
}
```

`type` is `amend`/`learn`/`remember`/`forget`/`rollback`; `trigger` is `user` or
`system` (learning loop); `approved_by` is `user` or `auto`.

## Rollback

`amend: rollback the last change to CLAUDE.md` / `amend: rollback all changes
from today`. Read the changelog to find the entry, restore `previous_value` to
the target file/section, and log a new entry with `type: "rollback"`.

## Learning loop

After completing a feature or complex bug fix, review the git diff and any review
feedback and ask: "What do I wish I'd known at the start?" Classify each insight
as a gotcha, pattern, anti-pattern, decision, or edge case. Capture only
non-obvious insights. Present proposals to the user; persist approved ones; log
with `trigger: "system"`.

Watch for recurring patterns: 3+ corrections on one topic → propose a `CLAUDE.md`
update; an agent consistently deferring to another → propose a collaboration
tweak; a skill repeatedly rejected → propose a guideline override; frequent
summarization → propose a loading-profile adjustment. At a minimum of 3
occurrences, propose with rationale; the user approves or rejects.

### Pending-review queue (closing the loop)

When the user isn't present to disposition a system proposal, enqueue it to
`metrics/pending-review.jsonl` (append-only) rather than dropping it:

```json
{
  "id": "2026-06-25T14:30:00Z-software-engineer-fp",
  "proposed_at": "2026-06-25T14:30:00Z",
  "trigger": "system",
  "source": "recurring-correction",
  "type": "amend",
  "description": "Software engineer keeps being corrected to prefer functional patterns (3 occurrences)",
  "target_file": "CLAUDE.md",
  "target_section": "Agent Overrides > Software Engineer",
  "proposed_value": "- Prefer functional programming patterns over OOP",
  "evidence": ["task-12", "task-15", "task-19"],
  "status": "pending"
}
```

`source` is `recurring-correction` or `post-task-reflection`; `evidence` lists
the motivating task ids (≥3 for a recurring correction); `status` is `pending`
until dispositioned. Before appending, scan for an open `pending` entry with the
same `target_file` + `target_section` + intent and skip duplicates.

### Session review (disposition)

On `review pending` / `session review`, list every `pending` entry with its
evidence, then for each:

1. **Preview** the proposed edit as a diff.
2. **Approve** → apply via the resolution table, log to `config-changelog.jsonl` with `approved_by: "user"`, then stamp the queue entry `status: "approved"`, `reviewed_at`, `approved_by`.
3. **Reject** → don't apply; stamp `status: "rejected"`, `reviewed_at`, `rejected_by`, optional `reason`.

Disposition updates the queue entry in place (distinct from the append-only
changelog). Batch the queue in one review pass rather than interrupting mid-task.

## Constraints

- Never edit read-only knowledge/agent cache files — all changes go to project-local files.
- Never auto-apply structural modifications without user preview.
- Behavioral tweaks (tone, preferences) may be auto-applied; structural changes (new sections, removed overrides) require approval.
- The changelog is append-only — never delete entries.
