---
name: threat-modeling
description: Structured STRIDE security analysis identifying threats, attack surfaces, and mitigations. Use before implementing a new API, service, authentication change, or data flow crossing trust boundaries — security analysis belongs in the design phase, not after.
model: claude-opus-4.8
metadata:
  tier: deep
---

# threat-modeling — STRIDE analysis at design time

Structured security analysis for identifying threats, attack surfaces, and mitigations during design or review. Ensures security is addressed before implementation, not after.

## Constraints

- Focus on trust boundaries, not implementation details.
- Every mitigation must map to a verifiable test or verification method.
- Document accepted risks explicitly with rationale; do not silently ignore threats.
- Revisit the threat model when architecture, authentication, or data flows change.

## Core Concepts

### STRIDE Classification

| Category | Definition | Example Threats |
| --- | --- | --- |
| **S**poofing | Pretending to be something/someone else | Forged auth tokens, impersonated services |
| **T**ampering | Modifying data or code without authorization | Altered request payloads, modified config files |
| **R**epudiation | Denying an action was performed | Unlogged admin actions, unsigned transactions |
| **I**nformation Disclosure | Exposing data to unauthorized parties | Leaked credentials in logs, verbose error messages |
| **D**enial of Service | Making a system unavailable | Resource exhaustion, unbounded queries |
| **E**levation of Privilege | Gaining access beyond authorization | Broken access control, privilege escalation via injection |

### Trust Boundaries

Points where data crosses privilege levels — every one is a potential attack surface: client↔server, service↔service (internal), application↔database, system↔external dependency, user role transitions.

### Attack Surface

Entry points exposed to untrusted input: API endpoints, file uploads, message queues, configuration inputs, user-supplied queries. Smaller surface means fewer threats to mitigate.

## Patterns

### Threat Identification Procedure

1. **Enumerate assets** — what needs protection (data, services, credentials, infrastructure).
2. **Draw trust boundaries** — where data crosses privilege levels.
3. **Identify entry points** — all inputs exposed to untrusted sources.
4. **Classify threats per STRIDE** — for each entry point, apply each STRIDE category and document applicable threats.
5. **Rate severity** — assess impact (critical/high/medium/low) and likelihood for each threat.

### Mitigation Mapping

| Threat Category | Standard Mitigations | Verification Method |
| --- | --- | --- |
| Spoofing | Authentication, mutual TLS, token validation | Auth integration tests, certificate verification |
| Tampering | Input validation, integrity checks, signed payloads | Tampering test cases, checksum validation |
| Repudiation | Audit logging, event sourcing, digital signatures | Log completeness review, signature verification |
| Information Disclosure | Encryption at rest/in transit, access controls, log scrubbing | Security scan, log audit, access control tests |
| Denial of Service | Rate limiting, resource quotas, circuit breakers | Load tests, resource monitoring |
| Elevation of Privilege | Least privilege, role-based access, input sanitization | Authorization test matrix, penetration tests |

### Threat Model Review Triggers

Revisit when any of these occur: new external dependency added; new API endpoint or entry point exposed; authentication or authorization changes; data flow changes crossing trust boundaries; infrastructure topology changes.

## When to Apply

| Scenario | Apply? |
| --- | --- |
| New service or API endpoint | Yes |
| New external integration | Yes |
| Authentication or authorization changes | Yes |
| Data flow crossing trust boundaries | Yes |
| Internal refactoring with no boundary changes | No |
| UI-only cosmetic changes | No |

## Guidelines

1. **Focus on trust boundaries, not implementation details.** Threats live at boundaries where privilege levels change.
2. **Mitigations must be verifiable.** Every mitigation maps to a test or verification method; unverifiable mitigations are theater.
3. **Document accepted risks explicitly.** When a threat is acknowledged but not mitigated, record the rationale, severity, and conditions for revisiting.
4. **Review when architecture changes.** The threat model is a living document.
5. **Severity drives priority.** Critical and high block implementation; medium and low are tracked and scheduled.
6. **Threat models are collaborative.** Improve them with input from architects, developers, and operations.

## Output

STRIDE threat table with severity ratings, mitigation mapping, and verification methods. Explicitly list accepted risks with rationale. Be concise — table format; group by STRIDE category.

## Integration

- Invoke during the Architecture Specification stage to identify security constraints before implementation; delegate adjacent design work via `/agent architect` (one agent at a time — sequential, aggregate).
- Threat documentation feeds compliance audit trails and security review records.
- Verify threat assessments against actual system state, not assumed state.
