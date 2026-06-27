---
name: semgrep-analyze
description: Run Semgrep static analysis on target files and return structured findings. Use when you want SAST scanning, static analysis, or a security scan — "run semgrep", "scan for vulnerabilities", "static analysis on this code" — or as a pre-review gate before review agents run.
model: claude-haiku-4.5
metadata:
  tier: small
---

# semgrep-analyze — run Semgrep, report findings

Worker pass: run Semgrep and report findings. **Do not fix code.**

## Constraints

1. **Do not modify code.** Report findings only.
2. **Return structured JSON** matching the output format below.
3. **Be concise.** No preambles, narration, or filler.

## Arguments

- `path` — directory or file to scan (default: current working directory).
- `--rules <ruleset>` — Semgrep ruleset (default: `auto`).
- `--programmatic` — return structured JSON only, no prose or status messages. For callers like the static-analysis pre-pass in `dt code-review`. When set, skip installation guidance on failure — just return the skip-status JSON.

Examples:

```text
semgrep scan (current dir, auto rules)
semgrep scan src/
semgrep --rules p/security-audit
semgrep src/utils --rules p/javascript
```

## Steps

### 1. Check Semgrep installation

```bash
semgrep --version
```

If not installed, output and stop:

```json
{"status": "skip", "issues": [], "summary": "semgrep not installed — install via pip install semgrep, pipx install semgrep, or brew install semgrep"}
```

If `--programmatic` is set, return the JSON above with no extra guidance.

### 2. Run Semgrep scan

```bash
semgrep scan --config <ruleset> --quiet --json <path>
```

Default ruleset `auto`. Default path `.`.

### 3. Parse results

| Semgrep field | Output field |
| --- | --- |
| `check_id` | `ruleId` |
| `extra.severity` | `severity` |
| `path` | `file` |
| `start.line` | `line` |
| `extra.message` | `message` |
| `extra.metadata.cwe` | `cwe` (if present) |

Severity mapping: `ERROR`→`error`, `WARNING`→`warning`, `INFO`→`suggestion`.

### 4. Output JSON

```json
{
  "status": "pass|warn|fail",
  "issues": [
    {
      "severity": "error|warning|suggestion",
      "file": "<path>",
      "line": 0,
      "ruleId": "<check_id>",
      "message": "<description>",
      "cwe": "<CWE-ID>",
      "suggestedFix": "<fix>"
    }
  ],
  "summary": "<N findings: N errors, N warnings, N suggestions>"
}
```

Status: `fail` if any errors, `warn` if warnings but no errors, `pass` if clean.

## Common Rulesets

| Ruleset | Description |
| --- | --- |
| `auto` | Auto-detect language, recommended rules |
| `p/javascript` | JavaScript-specific |
| `p/typescript` | TypeScript-specific |
| `p/react` | React-specific |
| `p/nodejs` | Node.js security |
| `p/security-audit` | General security audit |
| `p/owasp-top-ten` | OWASP Top 10 |
| `p/ci` | CI/CD-suitable |
| `p/default` | Semgrep default ruleset |
