---
name: static-analysis-integration
description: SARIF-first pre-pass that runs available static-analysis tools (semgrep, gitleaks, trivy, hadolint, actionlint) and normalizes output to one unified finding envelope, deduplicating across tools. Use as the static pre-pass before review agents so they focus on semantic concerns.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# static-analysis-integration — SARIF-first pre-pass

Run available static-analysis tools, normalize their output to the unified finding envelope (see `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/security-primitives-contract.md`), deduplicate across tools, and pass confirmed issues to review agents so they focus on semantic concerns.

Adapter/ruleset maintenance policies are out-of-runtime; they live in `~/.copilot/dev-team/knowledge/skills/static-analysis-integration/maintenance.md`.

## Constraints

1. **Collect and report only** — read source and tool output; make no code edits.
2. **Graceful degradation** — if no tools are installed, return `status: skip`; absence is never a pipeline failure.
3. **Deduplicate across tools** — the same issue reported by multiple tools appears once, attributed to the higher-priority source.

## Tool tiers

### Tier 1 — required baseline (SARIF native)

| Tool | SARIF invocation | Capability |
|---|---|---|
| semgrep | `semgrep scan --sarif --config auto` | SAST |
| gitleaks | `gitleaks detect --report-format sarif --report-path -` | secrets |
| trivy | `trivy config --format sarif <path>` + `trivy fs --format sarif <path>` | IaC + supply-chain |
| hadolint | `hadolint --format sarif <Dockerfile>` | IaC (Dockerfile) |
| actionlint | binary emits JSON; thin adapter maps to SARIF `result` (see `~/.copilot/dev-team/knowledge/skills/static-analysis-integration/references/tool-configs.md`) | CI/CD |

### Tier 2 — optional SARIF adapters

Not part of the baseline.

### Tier 3 — bespoke JSON adapters

For tools without upstream SARIF. Each adapter ≤ 40 LOC. A thin adapter normalizes `security-review` agent output into the unified envelope (see `~/.copilot/dev-team/knowledge/skills/static-analysis-integration/adapters/security-review-adapter.py`). Rule_id lookup is driven by `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/security-review-rule-map.yaml`; malformed categories hard-fail, well-formed-but-unmapped categories fall back to `security-review.*` with a WARN.

### Tier 4 — legacy (pre-SARIF)

ESLint / tsc / pylint remain callable via native JSON for older flows. Not part of the baseline; migrate to SARIF when upstream lands.

## Execution flow

### 1. Detect available tools

For each Tier 1 tool, run `command -v <tool>`. Record presence in a tool-map. Missing Tier 1 tools surface as a **warning group** via the install-hint format — never a pipeline failure.

If no Tier 1 tools are present, return:

```json
{ "status": "skip", "tools": [], "findings": [], "summary": "No static analysis tools detected." }
```

### 2. Run available tools

Run each available tool's invocation sequentially; collect SARIF on stdout (or via its adapter), keyed by tool name.

**The target walk MUST include CI/CD workflow files** even when they live outside the walked tree (monorepo case — walk up to the repo root):

- `.github/workflows/*.{yml,yaml}` (GitHub Actions)
- `.gitlab-ci.yml` + `.gitlab/**/*.{yml,yaml}` (GitLab CI)
- `.circleci/config.yml` (CircleCI)
- `azure-pipelines.yml` + `.azure-pipelines/**/*.{yml,yaml}` (Azure Pipelines)
- `bitbucket-pipelines.yml`
- `Jenkinsfile` + `jenkinsfile.d/**/*` (Jenkins)

Invoke every Tier-1 tool that can process them — actionlint for GitHub Actions, trivy-config for any CI YAML, semgrep with `p/github-actions` (or the bundled `crypto-anti-patterns.yaml` rule that catches `printenv` in workflow `run:` blocks).

Record which CI directories were scanned:

```json
{ "ci_dirs_scanned": [".github/workflows", ".gitlab-ci.yml"], ... }
```

If none found, record `"ci_dirs_scanned": []` so the caller can surface "no CI files in scope" when a CI config would be expected.

### 3. Normalize to the unified finding envelope

The shared SARIF parser (`~/.copilot/dev-team/knowledge/skills/static-analysis-integration/references/sarif-parser.md`) walks each document's `runs[*].results[*]` and emits one unified finding per result:

| SARIF path | Unified field | Notes |
|---|---|---|
| `results[*].ruleId` | `rule_id` | Prefixed: `<tool>.<lang?>.<rule>` |
| `results[*].locations[0].physicalLocation.artifactLocation.uri` | `file` | Repo-relative POSIX |
| `results[*].locations[0].physicalLocation.region.startLine` | `line` | 1-indexed |
| `results[*].locations[0].physicalLocation.region.startColumn` | `column` | 1-indexed, optional |
| `results[*].level` | `severity` | `error`→`error`, `warning`→`warning`, `note`→`suggestion`, `none`/absent→`info` |
| `results[*].message.text` | `message` | Truncated to 500 chars |
| `runs[*].tool.driver.rules[ruleIndex].properties.cwe` | `cwe[]` | If present: `["CWE-N"]` |
| `runs[*].tool.driver.name` | `metadata.source` | e.g. `"semgrep"` |
| result-level `properties.confidence` | `metadata.confidence` | Default `medium` if absent |

The parser MUST validate each emitted finding against unified-finding-v1 before returning; schema violations fail the run with a named tool + rule id.

### 4. Deduplicate

Two findings are duplicates if they share `file`, `line`, and either (a) identical `rule_id`, or (b) `message` cosine similarity > 0.85 on normalized text. Keep the higher-priority tool:

```
semgrep > gitleaks > trivy > hadolint > actionlint > (legacy ESLint > tsc > pylint)
```

### 5. Consult ACCEPTED-RISKS.md

If present at repo root, apply suppression per `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/accepted-risks-schema.md`. Suppressed findings are removed from the return value but logged to the audit trail.

### 6. Return structured result

```json
{
  "status": "pass|warn|fail",
  "tools_available": ["semgrep", "hadolint"],
  "tools_missing": [
    { "tool": "gitleaks", "install_hint": "gitleaks — secrets detection. install: brew install gitleaks" }
  ],
  "findings": [ /* unified finding envelope v1.0 objects */ ],
  "summary": "12 findings from 2 tools: 3 errors, 7 warnings, 2 suggestions"
}
```

`status`: `fail` if any finding has `severity: error`; `warn` if warnings only; `pass` if no findings or no tools available.

## Install-hint format

```
<tool-name> — <capability-tier>. install: <package-manager> install <name>
```

Examples:

```
semgrep — SAST. install: pip install semgrep
gitleaks — secrets detection. install: brew install gitleaks
trivy — IaC + supply-chain scanning. install: brew install trivy
hadolint — Dockerfile linting. install: brew install hadolint
actionlint — GitHub Actions linting. install: brew install actionlint
```

Print install-hints grouped by capability tier (secrets / IaC / CI-CD / supply-chain / SAST / data-flow). Required tools carry a `[REQUIRED]` prefix; absence of a required tool is a hard failure at install time, absence of an optional tool is a warning. Tier-implementation labels are internal vocabulary and never surface in user-facing text.

## Agent context injection

When findings are passed to review agents, format them so agents don't re-report confirmed static findings:

```text
## Static Analysis Pre-Pass Results

The following issues were detected deterministically by static analysis.
Do not re-report these issues. Focus on semantic and architectural concerns
that static analysis cannot detect.

| Tool | Severity | File | Line | Rule | Message |
|------|----------|------|------|------|---------|
| semgrep | error | src/api/handler.ts | 42 | javascript.express.audit.xss | Potential XSS |
| gitleaks | error | .env.example | 3  | generic.aws-access-key | AWS key pattern in committed file |
```

If no findings: "Static analysis pre-pass ran (tools: <list>). No findings — all clear."

This context goes to **all** review agents, not just security-review.

## Related

- `~/.copilot/dev-team/knowledge/skills/static-analysis-integration/references/tool-configs.md` — per-tool invocations, adapter scripts, install hints
- `~/.copilot/dev-team/knowledge/skills/static-analysis-integration/references/sarif-parser.md` — SARIF `result` → unified finding envelope v1.0
- `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/security-primitives-contract.md` — unified finding envelope v1.0
- `~/.copilot/dev-team/knowledge/skills/dev-team-knowledge/accepted-risks-schema.md` — per-project suppression policy
- `~/.copilot/dev-team/knowledge/skills/static-analysis-integration/maintenance.md` — adapter and ruleset lifecycle policies
