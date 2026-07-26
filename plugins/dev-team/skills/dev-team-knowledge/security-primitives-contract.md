---
name: security-primitives-contract
description: Versioned cross-plugin contract defining the data envelopes passed between dev-team and security-assessment. Agent IDs, skill IDs, three JSON schemas (RECON, unified finding, disposition register), and presentational severity mapping. Consumers declare `required-primitives-contract: ^1.0.0`.
version: 1.3.1
semver-policy: |
  PATCH (1.0.x) — clarifications, typo fixes, documentation improvements; no
                  schema changes.
  MINOR (1.x.0) — additive schema changes (new OPTIONAL fields, new enum
                  values, new agent IDs, new skill IDs, new guidance/
                  invariants enforced downstream). Consumers on prior
                  1.x.0 continue to work; new features ignored.
  MAJOR (x.0.0) — breaking changes (renamed or removed fields, changed
                  semantics, new REQUIRED fields, removed enum values).
                  Consumers on prior major MUST be updated.
---

# Security Primitives Contract v1.3.1

This file is the single source of truth for the data envelopes exchanged between the `dev-team` plugin (producer of primitives) and the `security-assessment` companion plugin (consumer). Downstream plugins declare compatibility via `required-primitives-contract: ^1.0.0` in their `plugin.json`.

> **Companion plugin not ported.** `security-assessment` is a separate upstream plugin that **this marketplace does not ship** (see `docs/upstream-v8-v10.md`). Every consumer-side agent, skill, script and schema named below is therefore a *contract obligation*, not a file on disk here. IDs are quoted bare (`fp-reduction`, not a path) precisely so nothing in this repo resolves to a phantom file. Producer-side entries — `codebase-recon`, `security-review`, `static-analysis-integration`, the three schemas — do ship here and carry real paths.

**Canonical schema registry**: this file is the single registry for every JSON/JSONL artifact shape shared or emitted in the security-assessment pipeline. Producer plugins (including the companion `security-assessment`) PR into this file rather than forking per-plugin contracts, so reviewers can trace any artifact back to one authoritative schema. New envelopes arrive as MINOR releases with `## Envelope N` sections plus changelog entries; per-tool raw outputs remain out of contract (see below).

The contract covers three data envelopes, two registries, and a presentational severity mapping. Per-tool raw outputs are **explicitly not in the contract** — they are normalized into the unified finding envelope by SARIF-first adapters in `skills/static-analysis-integration/SKILL.md`. That normalization layer is an implementation detail behind the contract, free to evolve under PATCH releases.

## Version-bump discipline

A body change without a `version` field bump is a contract defect: consumers pin on `required-primitives-contract` and cannot see an unversioned edit. Upstream enforced this with a `contract-version-guard.sh` PreToolUse hook; this port has no hook layer (hooks were replaced by TypeScript extensions), so the rule is carried by review, not by a guard. Release commits (author `release-please[bot]`, or commit-message prefix `chore(main): release`) are exempt — they bump the version themselves.

## Registries

### Agent IDs

Agents that produce or consume contract envelopes. Each ID is stable across the major version. Renames trigger a MAJOR bump.

| Agent ID | Produces | Consumes | Defined in |
|---|---|---|---|
| `codebase-recon` | RECON envelope | — | `plugins/dev-team/agents/codebase-recon.md` |
| `security-review` | unified findings | — | `plugins/dev-team/agents/security-review.md` |
| `fp-reduction` | disposition register | unified findings, RECON | companion plugin — `agents/fp-reduction.md` (not shipped here) |
| `tool-finding-narrative-annotator` | — | unified findings, RECON | companion plugin — `agents/tool-finding-narrative-annotator.md` (not shipped here) |
| `business-logic-domain-review` | unified findings (domain-level) | — | companion plugin — `agents/business-logic-domain-review.md` (not shipped here) |
| `cross-repo-synthesizer` | — | RECON, unified findings | companion plugin — `agents/cross-repo-synthesizer.md` (not shipped here) |
| `exec-report-generator` | — | all three envelopes | companion plugin — `agents/exec-report-generator.md` (not shipped here) |

Adding an agent ID is a MINOR bump. Removing one is a MAJOR bump.

### Skill IDs

Skills that participate in the contract (operate on envelopes or define adapter behavior).

| Skill ID | Role | Defined in |
|---|---|---|
| `static-analysis-integration` | SARIF-first adapters; produces unified findings from per-tool outputs | `plugins/dev-team/skills/static-analysis-integration/SKILL.md` |
| `false-positive-reduction` | Consumes unified findings, produces disposition register | companion plugin — `skills/false-positive-reduction/SKILL.md` (not shipped here) |
| `compliance-mapping` | Consumes unified findings, emits compliance annotations (not in contract — downstream-only) | companion plugin — `skills/compliance-mapping/SKILL.md` (not shipped here) |
| `security-assessment-pipeline` | Orchestrates full envelope flow end-to-end | companion plugin — `skills/security-assessment-pipeline/SKILL.md` (not shipped here) |

## Envelope 1 — RECON

Normalized reconnaissance output from `codebase-recon`. Schema: `skill://dev-team-knowledge/schemas/recon-envelope-v1.json`.

Key design notes:
- Superset of the `codebase-recon` v0.1 placeholder; `schema_version` bumps to `"1.0"`.
- Added under 1.0: `repo.vcs` object (distinguishes git from non-git repos), `architecture.notable_anti_patterns` (open-ended notes from the recon pass), `security_surface.csp_headers` (referenced in security contexts).
- All v0.1 field names remain stable.

### `file_inventory` (added in 1.2.0)

An authoritative enumeration of every file the recon considered in-scope at recon time. Gap 6's manifest-membership hook depends on this field — without it, consumers cannot answer "did a scan agent read a file outside the recon surface?" without their own tree walk.

The list itself ships as a **sibling file** (not embedded JSON) because mid-size repos produce 10k+ paths that bloat envelope diffs and validation cost. The main envelope carries a pointer and a count; the list lives at `memory/recon-<slug>.inventory.txt`.

**Shape** (main envelope, optional at schema level):

```json
"file_inventory": {
  "source": "git-ls-files" | "filesystem-walk",
  "count": <integer>,
  "sibling_ref": "recon-<slug>.inventory.txt"
}
```

All three sub-fields are required when the object is present. Object itself is optional so pre-1.2.0 envelopes stay schema-valid; `codebase-recon` always emits it from 1.2.0 forward.

**Sibling file contract** (`memory/recon-<slug>.inventory.txt`):

- UTF-8, LF line terminators, no BOM.
- One repo-relative path per line; path separator `/` on every platform; no leading `./`.
- Sorted lexicographically under `LC_ALL=C`; deduplicated.
- No blank lines. Final line is LF-terminated.
- No symlink entries — symlinks resolve to real-path targets; broken symlinks are skipped and recorded in the envelope's `notes` array.
- Plain text; not JSON; not validated by schema tooling.

**Enumeration pipeline** — upstream's canonical implementation is a `scripts/recon-inventory.sh`; **this port does not ship it**, so the `codebase-recon` agent performs the two branches inline and this section is the specification it follows. Both branches must produce the byte-shape above.

- **git branch** (target is a git working tree): `git ls-files -z --cached --others --exclude-standard`, then normalise per the rules above. `.gitignore` is authoritative; the excludes file is not consulted.
- **filesystem branch** (non-git target): walk the tree, pruning the directory prefixes and dropping the filenames listed in `plugins/dev-team/skills/dev-team-knowledge/recon-inventory-excludes.txt`.

Keeping the exclusion set in a data file rather than in the agent prompt is what makes the non-git branch reproducible across runs.

### Consumer error contract

Consumers that depend on `file_inventory` (e.g., Gap 6's PreToolUse hook, or any audit that wants to prove a reviewer didn't silently read outside the recon surface) **must fail-open** when any of the three branches below fires. Fail-open = emit a one-time informational notice to stderr in the exact format below, then proceed without the membership check. Never block the consumer's normal work; the inventory is a nice-to-have quality signal, not a correctness gate.

| Branch | Trigger | Stderr notice template |
|---|---|---|
| a | `file_inventory` field is absent on the envelope | `[recon-inventory] notice: file_inventory field absent on envelope; proceeding without membership check` |
| b | `file_inventory.sibling_ref` resolves to a file that is missing or unreadable at `memory/<sibling_ref>` | `[recon-inventory] notice: sibling file <path> missing; proceeding without membership check` |
| c | `file_inventory.count != wc -l <sibling>` (envelope declares N, sibling contains M, M != N) | `[recon-inventory] notice: file_inventory.count (<declared>) != wc -l <sibling> (<actual>); proceeding without membership check` |

Upstream backs this with `evals/primitives-contract/fixtures/consumer-stub-fail-open.sh` and `evals/primitives-contract/tests/backward-compat-1.2.0.sh`. Neither was ported (no `evals/` tree here), so the three templates above are the normative text — copy them verbatim rather than paraphrasing.

## Envelope 2 — Unified finding

Narrow normalization over SARIF `result` objects. Schema: `knowledge/schemas/unified-finding-v1.json`.

Required fields only. Per-tool raw output is NOT part of the contract (it is accessible via the `metadata.source_ref` field for debugging but consumers must not depend on its shape).

Required fields:
- `rule_id` — string, format `<source>.<language?>.<rule>` (e.g. `semgrep.python.hardcoded-password`, `gitleaks.generic.aws-access-key`)
- `file` — repo-relative path
- `line` — 1-indexed integer
- `severity` — enum: `error | warning | suggestion | info`
- `message` — one-line human-readable summary
- `metadata` — object with `source` (string: tool name), `confidence` (enum: `high | medium | low | none`)

Optional (at schema level):
- `column` — 1-indexed integer
- `end_line`, `end_column`
- `cwe`, `cve`, `owasp` — string arrays
- `metadata.source_ref` — opaque pointer to the raw tool output (debugging aid only; not stable)
- `metadata.exploitability` — enum: `demonstrated | plausible | theoretical | unknown`

**Strongly recommended at schema; enforced downstream (added in v1.1.0):**

- `cwe` is **strongly recommended** for every finding with `severity: error` or `severity: warning`. The schema keeps `cwe` optional for backward compatibility with adapters that do not emit it (hadolint, actionlint, some trivy config rules). The `exec-report-generator` (Phase B Step 14) **rejects** findings without CWE from CRITICAL / HIGH sections of the exec report with a named error, and lists them in an appendix for follow-up.
- CRITICAL / HIGH presentational findings (see § Severity mapping below) **must** carry a reachability trace. The trace lives on the finding's disposition entry, not on the finding itself. The exec-report-generator enforces this too.

## Envelope 3 — Disposition register

Output of `fp-reduction` over unified findings. Schema: `knowledge/schemas/disposition-register-v1.json`.

One disposition entry per unified finding processed. Each entry:
- `finding` — the unified finding being dispositioned (embedded verbatim, not a reference)
- `verdict` — enum: `true_positive | likely_true_positive | uncertain | likely_false_positive | false_positive`
- `reachability` — object: `{ reachable: bool, rationale: string }`
- `reachability_source` — enum: `joern-cpg | llm-fallback` (drives exec report's fallback banner per P2 Phase B)
- `exploitability` — object: `{ score: 0-10, rationale: string }`
- `dispositioner` — string: agent ID that produced this disposition (typically `fp-reduction`)
- `dispositioned_at` — ISO-8601 timestamp

## Envelope 4 — Accepted-risks log (added in v1.3.0)

Per-target suppression log emitted by `scripts/apply-accepted-risks.sh` in the companion plugin (not shipped here). Written to `<memory-dir>/accepted-risks-<slug>.jsonl`. Source-of-truth input is `<target-dir>/ACCEPTED-RISKS.md` — the input format this port ships is `skill://dev-team-knowledge/accepted-risks-schema.md`.

Two record shapes, discriminated by the `status` field:

**Suppression record** — an active accepted-risks entry matched a finding and that finding was removed from `findings-<slug>.jsonl`:

```json
{
  "status": "suppressed",
  "rule_id": "semgrep.csharp.sqli.raw-sql-concat",
  "source_ref": "src/Legacy/Query/Foo.cs",
  "source_ref_glob": "src/Legacy/**/*.cs",
  "reason": "Legacy reporting module scheduled for deletion Q3 2026 (ACI-RPT-1234).",
  "expires": "2026-09-30",
  "iso": "2026-04-24T17:30:39Z"
}
```

**Expired-entry record** — an ACCEPTED-RISKS.md entry's `expires` date has passed; the script logs the lapse but does NOT suppress any finding:

```json
{
  "status": "expired",
  "rule_id": "hadolint.DL3003",
  "source_ref_glob": "docker/base/Dockerfile",
  "reason": "Base image built in a controlled CI step; cd is intentional.",
  "expires": "2020-01-01",
  "iso": "2026-04-24T17:30:39Z"
}
```

Field invariants:
- `status` ∈ `{"suppressed", "expired"}`.
- `rule_id`, `source_ref_glob`, `reason`, `expires`, `iso` are required on both shapes.
- `source_ref` is required only on `status:"suppressed"` (it records the specific finding that matched).
- `expires` is `YYYY-MM-DD` UTC.
- `iso` is ISO-8601 UTC (second precision suffices; the log is for audit, not tracing).

Idempotency: the script rewrites (does not append to) the log file on each run, so a re-run against unchanged inputs produces a byte-identical file.

## Envelope 5 — Severity-floors log (added in v1.3.0)

Per-target floor-application log emitted by `scripts/apply-severity-floors.sh` in the companion plugin. Written to `<memory-dir>/severity-floors-log-<slug>.jsonl`. The script raises `exploitability.score` on matched disposition entries (Envelope 3) and emits one JSONL record per match.

```json
{
  "id": "sec-appsettings.json-511",
  "floor_class": "hardcoded-creds",
  "floor": 9,
  "original_score": 9,
  "final_score": 9
}
```

Field invariants:
- `id` matches an entry `id` in the disposition register.
- `floor_class` comes from the `<class> floor=<n>` pattern embedded in the entry's `exploitability.rationale` (fp-reduction agent convention) AND must appear in the companion plugin's `knowledge/severity-floors.json` `recognized_classes` (not shipped here — a consumer-side obligation).
- `floor`, `original_score`, `final_score` are integers in 0..10.
- `final_score >= original_score` (floors only raise).
- `final_score >= floor` (the floor was respected).
- Records are emitted for every matched entry on first run, even when `original_score == final_score` (log-every-match semantics, matching the 2026-04-24 extranetapi reference).

Idempotency: the script sets `exploitability.floor_applied: true` on each mutated entry; subsequent runs skip marked entries, so the log file is append-safe across re-runs against an already-floored register.

Suppression phrase: entries whose rationale contains `floor=<n> suppressed to <m>` are skipped entirely (the fp-reduction agent signaled the default floor does not apply in context) — no log record is emitted.

## Severity mapping (added in v1.1.0)

The unified finding envelope uses a lint-grade severity scale optimized for tool output (`error | warning | suggestion | info`). The `exec-report-generator` maps these into a **presentational** CRITICAL / HIGH / MEDIUM / LOW scale for executive-audience reports. The presentational scale matches the `opus_repo_scan_test` reference and is familiar to CISO / CTO readers.

The mapping combines the finding's `severity` with its disposition-register `exploitability.score` (0–10) and `metadata.exploitability` enum. The scale is presentational only — findings remain stored at the narrower schema-level severity.

| Presentational | Definition | Driven by |
|---|---|---|
| **CRITICAL** | Immediate exploitation, data breach, or fraud bypass. Demands same-day remediation. | `severity: error` AND (`exploitability.score >= 7` OR `metadata.exploitability: demonstrated`) |
| **HIGH** | Exploitable with moderate effort, significant impact. Demands same-week remediation. | `severity: error` AND `exploitability.score` in `[4, 6]`; OR `severity: warning` AND `exploitability.score >= 7` |
| **MEDIUM** | Requires specific conditions or insider access. Addressed in normal release cycle. | `severity: warning` AND `exploitability.score` in `[3, 6]`; OR `severity: error` AND `exploitability.score < 4` |
| **LOW** | Informational or defence-in-depth. No immediate action. | `severity: suggestion`, or `severity: warning`/`error` with `exploitability.score < 3`, or `severity: info` |

Tie-breaks:
- A finding with `verdict: false_positive` never reaches the presentational scale; suppressed from the report.
- `verdict: likely_false_positive` downgrades one presentational level (CRITICAL → HIGH → MEDIUM → LOW).
- A finding without a disposition entry (happens when FP-reduction is bypassed) is presented at one level lower than the mechanical mapping would give, with a footnote noting FP-reduction was skipped.

### Downstream invariants

The `exec-report-generator` enforces these invariants and rejects (with named errors) any finding that violates them from CRITICAL / HIGH sections. LOW findings can bypass all three:

1. **CWE required** on CRITICAL and HIGH. Findings without CWE appear in an appendix labelled "Findings missing CWE — investigate" for the audit trail.
2. **Reachability trace required** on CRITICAL and HIGH. The trace comes from the disposition entry's `reachability.rationale` (min 20 chars per schema). Missing → same appendix.
3. **Dedup applied**. One credential appearing in N config variants is one finding with N locations, not N findings.

## Out of contract

Explicitly NOT part of this contract:

- Per-tool raw outputs (SARIF documents, JSON outputs from bespoke adapters). These flow through the adapter layer and are normalized into unified findings. Consumers treat adapters as opaque — the unified finding envelope is the contract boundary.
- Internal adapter configuration (`references/tool-configs.md` layouts, matcher regexes). These are implementation details of `skills/static-analysis-integration`.
- Compliance mapping outputs. These are a downstream product of the companion plugin, not shared cross-plugin primitives.
- Report templates (executive report sections, Mermaid diagrams). These are presentation concerns.
- Red-team harness artifacts. The harness ships its own schemas under the companion plugin's `harness/redteam/schemas/` — separate lifecycle, separate versioning.

## Conformance

Schemas live at `plugins/dev-team/skills/dev-team-knowledge/schemas/` — `recon-envelope-v1.json`, `unified-finding-v1.json`, `disposition-register-v1.json` — and must validate using any Draft 2020-12 JSON Schema validator. From an agent: `read skill://dev-team-knowledge/schemas/<name>-v1.json`.

Upstream's conformance fixtures (`evals/primitives-contract/fixtures/`, plus the mutation test and the version-mismatch mock that exercises the installer's refusal path) were **not ported** — there is no `evals/` tree under this plugin. What CI does enforce here is `scripts/ci-validate-json.mjs` (every shipped JSON parses) and `scripts/ci-framework-compliance.mjs` (every `plugins/...` path named in markdown resolves, so a schema rename cannot silently orphan this section). Restoring the fixtures is the open gap; agent IDs cited elsewhere in the plugin must match the registry above.

## Versioning lifecycle

- Clarifications and typos → open a PR with `version: 1.0.X` (PATCH).
- New optional fields, new enum values, new agent or skill IDs, new guidance or invariants enforced downstream → `version: 1.X.0` (MINOR). Update the relevant schema file; add a fixture; document the addition under `## Changelog`.
- Removing a field, renaming a field, changing a field's semantics, or adding a REQUIRED field → `version: X.0.0` (MAJOR). Publish a migration note; downstream plugins' `required-primitives-contract` constraints force them to update before installing.

## Changelog

### 1.3.1 (2026-07-26)

PATCH — documentation only. No schema file changed; no field added, removed or re-meant. Consumers on `^1.0.0` are unaffected.

- **Dead paths corrected.** Every reference that used upstream's top-level `knowledge/` directory pointed at a path that does not exist in this port; the corpus lives at `plugins/dev-team/skills/dev-team-knowledge/`. The three schemas, the excludes file and the accepted-risks format now resolve.
- **Companion-plugin references de-pathed.** Full paths into the `security-assessment` plugin named files this marketplace does not ship. The agent and skill IDs stay (they are the versioned contract); only the phantom paths are gone, replaced by a "not shipped here" marker per row and a banner in the preamble.
- **Unported implementations named as such.** `scripts/recon-inventory.sh` and the `evals/primitives-contract/` fixtures do not exist here. The enumeration pipeline is now *specified* in this file — git-ls-files branch, filesystem-walk branch, byte-shape — and `codebase-recon` implements it inline against that spec.
- **Bypass section rewritten.** It described a `contract-version-guard.sh` PreToolUse hook; this port has no hook layer, so the version-bump rule is stated as review-enforced rather than as a guard that does not exist.

### 1.3.0 (2026-04-24)

Additive schema release. Consumers on `^1.0.0` continue to install unmodified.

- **New Envelope 4 — Accepted-risks log.** Registers the `<memory-dir>/accepted-risks-<slug>.jsonl` artifact emitted by the companion plugin's new `scripts/apply-accepted-risks.sh` (Phase 1c). Two record shapes: `status:"suppressed"` and `status:"expired"`. Input format reference lives in the companion plugin's `docs/accepted-risks-format.md`; the format this port ships is `skill://dev-team-knowledge/accepted-risks-schema.md`.
- **New Envelope 5 — Severity-floors log.** Registers the `<memory-dir>/severity-floors-log-<slug>.jsonl` artifact emitted by the companion plugin's new `scripts/apply-severity-floors.sh` (Phase 2b). Schema matches the 2026-04-24 extranetapi reference byte-for-byte.
- **New canonical-registry paragraph** in the preamble making explicit that this file is the single registry for artifacts shared between the two plugins. Addresses an architecture-review observation during the helper-scripts PR that producers should PR into this file rather than fork per-plugin contracts.
- **Backward compatibility:** pre-1.3.0 plugin installations continue to work — the new envelopes have no producers outside the new helper scripts, and the existing envelopes are unchanged.

### 1.2.0 (2026-04-24)

Additive schema release. Consumers on `^1.0.0` continue to install unmodified.

- **New field:** Envelope 1 now carries an optional `file_inventory` object (`source` enum, `count` integer, `sibling_ref` string). The actual path list ships as a sibling file `memory/recon-<slug>.inventory.txt` to keep JSON diffs small on large repos.
- **New subsection:** `### Consumer error contract` under Envelope 1 documents the three fail-open branches (field absent, sibling absent, count mismatch) with exact stderr notice templates. Upstream's reference implementation (`evals/primitives-contract/fixtures/consumer-stub-fail-open.sh`) was not ported; the templates below are the spec.
- **New canonical enumeration pipeline:** upstream's `scripts/recon-inventory.sh` is the single source of truth for both the git-ls-files branch and the filesystem-walk branch. This port has no `scripts/` layer under the plugin, so `codebase-recon` implements both branches inline against the spec in this file; excludes for the non-git branch live in `plugins/dev-team/skills/dev-team-knowledge/recon-inventory-excludes.txt`.
- **Backward compatibility:** pre-1.2.0 envelopes continue to validate. Consumers that need the field (Gap 6's manifest-membership hook) follow the fail-open contract documented above.

### 1.1.0 (2026-04-21)

Additive guidance release. Schema files unchanged; consumers on `^1.0.0` work unmodified.

- **New section:** Severity mapping from unified `severity` + disposition `exploitability` into presentational CRITICAL / HIGH / MEDIUM / LOW. Matches the `opus_repo_scan_test` reference's severity framework so executive-audience reports are comparable.
- **New invariants (enforced by `exec-report-generator`, not by schema):** CWE required on CRITICAL / HIGH; reachability trace required on CRITICAL / HIGH; dedup applied before reporting. Findings violating these are reported in a dedicated appendix rather than silently dropped.
- **Backward compatibility:** adapters that do not emit CWE (hadolint, actionlint, some trivy config rules) continue to work; their findings land at MEDIUM or LOW unless FP-reduction's exploitability scoring elevates them — in which case the CWE-missing appendix notifies reviewers.

### 1.0.0 (2026-04-21)

Initial contract. Finalizes the RECON envelope v0.1 placeholder from `codebase-recon`. Defines unified finding envelope as a narrow SARIF `result` normalization. Defines disposition register as the FP-reduction output envelope. Registers initial agent and skill IDs.
