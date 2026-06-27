---
name: adr-tools
description: Create and manage Architecture Decision Records using the adr-tools CLI (npryce/adr-tools). Use when asked to "add an ADR", "record this decision", "supersede ADR N", "link ADRs", or "generate the ADR table of contents". This is the mechanics (commands, files, links); pair with the adr-author agent for the decision framework and prose.
model: claude-haiku-4.5
metadata:
  tier: small
---

# adr-tools — driving the `adr` CLI

Mechanics for working with [npryce/adr-tools](https://github.com/npryce/adr-tools) — the `adr` CLI that creates numbered Architecture Decision Records. Pair with `/agent adr-author`: that agent decides *whether* an ADR is warranted and writes the prose; this skill drives the CLI correctly.

## Pre-flight

```bash
command -v adr || echo "adr-tools not installed — see https://github.com/npryce/adr-tools"
cat .adr-dir 2>/dev/null   # project's configured ADR directory
ls "$(cat .adr-dir 2>/dev/null || echo docs/adr)/" 2>/dev/null | head -3
```

Project convention is `docs/adr/`. `adr-tools` stores the directory in `.adr-dir` at the project root — `adr` reads that file no matter what subdirectory you're in. If `.adr-dir` is missing, run `adr init docs/adr` once. Do not init silently into a different path — confirm with the user if existing ADRs live somewhere unexpected.

## Editor caveat — the most common failure

`adr new` opens `$VISUAL` or `$EDITOR` (defaulting to `vi`). In a non-interactive agent shell this hangs the command and exits non-zero — the file is created but empty. Two workarounds:

1. **Preferred — bypass the editor.** Run with a no-op editor, then write the body yourself:

   ```bash
   EDITOR=true VISUAL=true adr new "<title>"
   ```

   The command prints the new file path to stdout. Read it, then replace the template Context/Decision/Consequences sections with the real content via Edit or Write.

2. **Fallback — let it fail, then fill in.** `adr new "<title>"` creates the templated file and exits non-zero from the editor failure. Read the new file (at `<adr-dir>/NNNN-<slugified-title>.md` — typically `docs/adr/`) and fill it in.

Always prefer workaround 1.

## Workflows

### Create a new ADR

```bash
EDITOR=true VISUAL=true adr new "<title in plain words>"
```

Then edit the generated file to fill in:

- **Status** — `Accepted` (default) for decisions already made. Use `Proposed` only if there is genuine open debate.
- **Context** — what forces drove this decision (constraints, alternatives, prior art).
- **Decision** — what we are doing (active voice, present tense: "Adopt X" not "We will adopt X").
- **Consequences** — easier / harder / risks. Be specific. If you cannot name a concrete trade-off, the decision probably did not need an ADR.

Commit the new ADR in the same commit (or PR) as the implementation it justifies.

### Supersede an earlier ADR

```bash
EDITOR=true VISUAL=true adr new -s <N> "<new title>"
```

`adr-tools` automatically inserts a "Supersedes [ADR N]" link in the new ADR's Status section and edits ADR N's Status to "Superseded by [ADR M]". Do not delete the old ADR — its history is the point.

### Link two ADRs without superseding

```bash
adr link <SOURCE> "<LINK>" <TARGET> "<REVERSE-LINK>"
```

Example: `adr link 12 "Amends" 10 "Amended by"`. Use for relationships like Amends/Refines/Constrains. Multiple links are normal.

### List all ADRs

```bash
adr list
```

Returns sorted file paths. Pipe through `xargs head -1` for a quick title scan.

### Generate the table of contents

```bash
adr generate toc > docs/adr/README.md
```

Run this after creating or superseding any ADR, then commit the regenerated TOC alongside the change. Without this, the index drifts.

### Generate the dependency graph

```bash
adr generate graph | dot -Tpng > docs/adr/graph.png
```

Optional but useful when supersede/link chains get deep. Requires Graphviz (`dot`).

## Anti-patterns to refuse

- **Don't renumber ADRs.** Numbers are stable references in commits, PRs, and other ADRs. If a number is wrong, supersede; never renumber.
- **Don't edit ADR status with a text editor when superseding.** Use `adr new -s <N>` so the bidirectional link is automatic and consistent.
- **Don't squash multiple decisions into one ADR.** One decision per file. If a Decision section has bullets that aren't facets of the same choice, split.
- **Don't write Decision in future tense.** "Adopt X" reads as a decision; "We will adopt X" reads as a proposal. Use the former for `Accepted` status.
- **Don't omit Consequences.** An ADR without trade-offs is a note. If there genuinely are none, the decision did not need an ADR.

## When to defer to adr-author

This skill handles CLI mechanics. Use `/agent adr-author` when:

- It is unclear whether the change *warrants* an ADR (its decision framework).
- The decision has policy or architectural implications and you want prose with the right scope.
- You need to maintain the ADR index README beyond what `adr generate toc` produces.

Typical flow: user asks "should we ADR this?" → adr-author decides yes/no and drafts the body → this skill runs the `adr new` / `adr link` commands and regenerates the TOC.
