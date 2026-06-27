---
name: semantic-duplication-scan
description: Detect business logic reimplemented across architectural layers. Builds a persistent computation-register.json by annotating non-trivial computation functions, then clusters them to surface duplicate domain concepts. Full-scan on first use, incremental (git-diff) after. Use to find logical duplication linters miss.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# semantic-duplication-scan — cross-layer semantic equivalence

Detect business logic reimplemented across layers. Unlike linters (syntactic similarity) or `arch-review` (single-instance layer violations), this catches semantic equivalence — the same domain calculation independently appearing in domain services, client adapters, and presentation components with different names and structure.

This is a multi-stage pipeline. Run the stages sequentially in one agent — annotate, then cluster, then resolve — and switch tiers with `/model` where noted (cheap tier for bulk annotation, standard tier for clustering, deep tier for ambiguous canonical resolution). Do not spawn parallel agents.

## Annotation Prompt Version

**promptVersion**: `1.0` — when this changes, any register entry with a different `promptVersion` is stale and re-annotated on the next pass touching that file.

## Pre-Filter Rules

**Apply before any model call. No model invocation at this stage.**

### Trivial Function Definition

A function is **trivial** (excluded) if it meets ALL of:
- No arithmetic operators: `+`, `-`, `*`, `/`, `%`, `**`
- No boolean logic: `&&`, `||`, `!`, `not`, `and`, `or`
- No branching: `if`, `else`, `switch`, `case`, ternary (`?:`), `match`
- No assignments to variables outside its own scope (no external state mutation)
- No higher-order collection ops: `map`, `filter`, `reduce`, `flatMap`, `forEach`, `find`, `some`, `every`, or equivalents

Always-trivial patterns: getters, pass-through delegators, identity functions, constructors that only assign params to fields.

If a file contains **only trivial functions**, output `No computation units found to analyze` and do not create or modify the register.

### File Exclusion Patterns

Exclude regardless of content:

```
*.test.*   *.spec.*   __tests__/   *.test-d.*   *.generated.*
*.pb.*   *.d.ts   dist/   build/   .next/   coverage/
```

Also exclude any path matching a glob in `.semanticscanignore` (one glob per line) if present in the project root.

## Process Flow

### Step 1 — Mode Detection

Check for `computation-register.json` in the project root: absent → full-scan; present → incremental.

### Step 2 — Pre-Flight (Incremental Only)

Run `git rev-parse --is-shallow-repository`. If `true`, output exactly `Shallow clone detected — semantic-scan requires full history for incremental mode. Run with --full to override.` and exit non-zero.

If `--full` was passed, skip this check and force full-scan.

If `lastScanCommit` is not in git history, output `lastScanCommit not found in history — running full scan` and switch to full-scan.

### Step 3 — Scope Resolution

1. If a path argument was provided, use it as a prefix filter.
2. Apply `.semanticscanignore` patterns.
3. Apply the file exclusion patterns above.

### Step 4 — File Selection

- **Full-scan**: glob all source files in scope.
- **Incremental**: `git diff <lastScanCommit> HEAD --name-only`, then filter to scope.

If the diff is empty: update `lastScanCommit` to HEAD, write the register, output `No changes since last scan — register up to date`, exit 0.

### Step 5 — Pre-Filter

For each selected file, identify non-trivial computation functions using structural heuristics (no model call). If none remain:
- **First run**: `No computation units found to analyze` → exit 0, no register.
- **Incremental run**: `No new computation units found in changed files — register unchanged` → exit 0, register untouched.

### Step 6 — Annotation (cheap `/model` tier, file-level batching)

For each file with non-trivial functions:
1. Emit progress to stderr: `Annotating [N/total] <filename>`.
2. Send all non-trivial functions from the file in a single call using the pinned prompt below.
3. If the call fails, record `{file, error}` in `scanErrors` and continue — do not abort.

**Annotation prompt (pinned — do not paraphrase):**

```
You are a semantic annotation assistant. For each function below, produce a JSON object describing what it computes in pure domain business terms.

Use this schema:
{
  "function": "<function name>",
  "layer": "<inferred layer — see rules below>",
  "semanticDescription": {
    "verb": "<lowercase infinitive verb>",
    "domainConcept": "<lowercase, no articles, normalized>",
    "inputs": ["<domain term>", ...],
    "outputConcept": "<domain term>"
  }
}

Layer inference rules — infer from what the function imports and uses:
- "infrastructure": imports DB clients, ORMs, HTTP clients, message brokers (pg, redis, axios, fetch, prisma, mongoose, etc.)
- "presentation": imports rendering primitives, formats for display, accesses DOM or templates (React, Vue, Svelte, JSX, HTML templates, etc.)
- "domain": depends only on domain types and pure functions, no external imports
- "application": orchestrates domain and infrastructure without owning business rules
- "unknown": cannot be determined from available context

domainConcept rules:
- Use lowercase
- Remove articles: a, an, the
- Normalize the verb to infinitive form
- Example: "calculates the discounted price" → domainConcept: "discounted price", verb: "calculate"

Describe only what the function computes in domain terms. Do not reference the implementation language, variable names, or data structure types.

Functions:
<paste function source here>
```

**Canonicalize `domainConcept` after the response:** lowercase; strip leading/trailing articles (`a `, `an `, `the `); normalize the `verb` field to infinitive.

### Step 7 — Register Update

Build a register entry per annotated function:

```json
{
  "file": "<relative path from project root>",
  "function": "<function name>",
  "layer": "<inferred layer>",
  "semanticDescription": {
    "verb": "<canonicalized>",
    "domainConcept": "<canonicalized>",
    "inputs": ["<domain term>", ...],
    "outputConcept": "<domain term>"
  },
  "promptVersion": "1.0",
  "commitHash": "<HEAD commit hash>",
  "line": <first line of function definition>
}
```

**Merge strategy:** replace all entries whose `file` was re-annotated; remove entries for files no longer on disk; remove entries for files matching `.semanticscanignore`; preserve all others.

**Idempotency:** sort entries by `file` ascending, then `function` ascending, before writing.

**Write the register.** On write failure (permissions, disk full): output the exact path and OS error, exit non-zero.

**Update `lastScanCommit`** to current HEAD after a successful write.

**Report partial failures** (only if `scanErrors` non-empty): N=1 → `Warning: 1 file could not be annotated. Re-run to retry.`; N>1 → `Warning: N files could not be annotated. Re-run to retry.` Exit 0 — partial success is not a failure.

## Clustering

### Token Budget and Partitioning

Shard the register by layer pair before clustering:
- `domain × presentation`, `domain × infrastructure`, `application × presentation`, `application × infrastructure`, `domain × application`.

If a shard exceeds **50,000 tokens**, further shard by the first normalized token of `domainConcept` (alphabetical sub-groups).

After per-shard clustering, run a **cross-shard reconciliation pass**: send only cluster representatives (top-ranked candidate per cluster) back through clustering to catch equivalents in different shards. Keep the merge input under 50,000 tokens.

### Clustering Call (standard `/model` tier)

For each shard, emit progress: `Clustering [layer-pair]: <layer-a> × <layer-b>...`

**Clustering prompt (pinned — do not paraphrase):**

```
Group these register entries by semantic equivalence — entries that compute the same domain concept regardless of implementation differences. Return clusters as JSON arrays of entry IDs (use "file:function" as the ID).

Two entries belong in the same cluster ONLY IF both would need to change if the underlying business rule changed.

Input entries:
<paste shard entries as JSON array>

Return only:
{ "clusters": [["file1:funcA", "file2:funcB"], ...] }

Entries that are semantically unique should not appear in any cluster.
```

## Canonical Scoring

For each cluster of 2+ entries:

**Layer rank** (higher = more canonical): `domain` > `application` > `presentation` > `infrastructure` > `unknown`.

**Within the same layer rank:** count infrastructure imports in the function's file; fewer = higher rank.

**Ambiguity predicate:** if the top two candidates tie on layer rank AND differ by ≤1 infrastructure import → escalate to the deep `/model` tier.

Before the deep-tier call, emit: `Resolving ambiguous canonical for cluster: <domainConcept>...`

**Canonical-resolution prompt (deep tier):**

```
Given these N entries that all compute the same domain concept, which one is the most appropriate canonical location for the business rule? Consider: domain purity, reusability, and least coupling to delivery mechanism. Return the file:function ID of the preferred canonical and a one-sentence rationale.

Entries:
<paste cluster entries>
```

If `--no-opus` was passed: skip the deep-tier escalation (stay on a cheaper `/model` tier). Report ambiguous clusters as `canonical: ambiguous — human review required`.

### Canonical Verdict Output

- Clear winner (domain or application layer, no tie): `canonical: suggested <file:line> — requires human confirmation`
- No winner (all infrastructure/unknown, or tie unresolved): `canonical: none — a new domain-layer implementation may be required`

**Cross-scope notice** (scoped runs only): if a cluster contains entries outside the scoped path: `Note: this cluster includes <N> entry/entries outside the scoped path — run without scope argument to see full context` (use "entry" for N=1, "entries" for N>1).

## Report

**Duplicates found:**

```
## Semantic Duplication Report

### Cluster: <domainConcept>

  - <file>:<line> [<layer>]  ← inferred canonical (or all entries if no canonical)
  - <file>:<line> [<layer>]

  canonical: suggested <file:line> — requires human confirmation
  [Note: this cluster includes N entry/entries outside the scoped path ...]

---
```

**No duplicates:** `No semantic duplication detected`

**`file:line` accuracy:** line numbers point to the first line of the function definition. If the file was modified since annotation, append `(line may have shifted — re-run scan to refresh)`.
