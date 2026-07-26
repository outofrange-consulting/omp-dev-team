# Static Analysis Integration — Maintenance Policies

These policies cover the lifecycle of adapters and rulesets shipped with this skill. They are read by maintainers, not by agents at runtime — the runtime skill is in `SKILL.md`.

## Adapter Maintenance Policy

Adapters (SARIF wrappers, bespoke JSON adapters) have a lifecycle independent of the tools they wrap.

- **Owners**: the skill's `maintainers:` frontmatter list. Minimum 2 names.
- **Update trigger**: schema drift in a wrapped tool breaks the adapter. Upstream detects this with a nightly tier-2 job that runs each adapter against the installed binary; **this port ships no such job** — `.github/workflows/installers.yml` runs lint / ctx-wire filters / bun build + `tsc --noEmit` / framework compliance / e2e install, none of which exercise an adapter against a real tool. Until that job exists, drift surfaces as a failed `/code-review` pre-pass in the field, not in CI. Treat that as the known gap, not as a covered case.
- **Escalation**: an unassigned adapter-drift report older than 14 days escalates to CODEOWNERS.
- **Deprecation**: an adapter that is broken for three consecutive releases AND whose upstream tool has been unmaintained for > 6 months is demoted to "deprecated" — still shipped, emits a warning on invocation, removed in the next MAJOR contract version.
- **Adding a tool**: requires (a) a fixture pair — one input the tool would emit plus the expected unified finding — and (b) a SARIF adapter first; bespoke-JSON only if upstream genuinely has no SARIF plan. The fixture pair has nowhere to live until the eval tree is ported; carry it in the PR description meanwhile.

## Ruleset Maintenance Policy

Separate lifecycle from adapters — rulesets track evolving attack patterns, not tool schema drift.

- **What ships here.** This plugin ships **no semgrep rulesets**. Custom `.yaml` rules belong to the upstream `security-assessment` companion plugin, which this marketplace does not ship. What *is* shipped is the detection surface those rules are held to: the class → surface boundary in `skill://dev-team-knowledge/security-review-rule-map.yaml`, and the positive/negative code fixtures per OWASP class under `plugins/dev-team/skills/dev-team-knowledge/rule-fixtures/` (11 classes, each a `positive` + `negative` pair). The policies below apply to those fixtures and to any ruleset a downstream plugin adds against this contract.
- **Owners**: each ruleset carries a `maintainers:` frontmatter block with ≥ 2 names.
- **Review cadence**: quarterly. Reviewers confirm patterns are still relevant, add new attack signatures, retire deprecated ones.
- **FP drift threshold**: a rule that fires on its class's `negative.*` fixture is a false positive by construction; a class whose fixtures show > 20% FP noise is paused and triaged within one release.
- **Community-PR intake**: a PR adding a pattern requires a positive fixture **and** a negative fixture in the matching `rule-fixtures/<class>/` directory. Rejections must cite the policy.
- **Deprecation**: a ruleset with no review or change in two consecutive review cycles is demoted to "archived" unless a maintainer re-ups.
