---
description: Never disable tests, linters, or analyzers to force a pass — fix the root cause
globs:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
  - "**/*.py"
  - "**/*.go"
  - "**/*.rs"
  - "**/*.java"
  - "**/*.kt"
  - "**/*.cs"
  - "**/.eslintrc*"
  - "**/eslint.config.*"
  - "**/biome.json*"
  - "**/.editorconfig"
  - "**/ruff.toml"
  - "**/pyproject.toml"
  - "**/*.csproj"
  - "**/Directory.Build.props"
  - "**/.golangci.y*ml"
---

# Quality gates are non-negotiable

**Never weaken a quality gate to make a build, test, or check pass. Fix the
cause.** A green run obtained by silencing the signal is a regression, not a fix.

Specifically, do **not**, in order to clear a failure:

- Add or widen a suppression: `// eslint-disable*`, `# noqa`, `# type: ignore`,
  `#pragma warning disable`, `[SuppressMessage]`, `@ts-ignore`/`@ts-expect-error`,
  `-Wno-*`, `// nolint`.
- Lower strictness: drop `warnaserror`/`TreatWarningsAsErrors`, lower
  `AnalysisMode`, relax `tsconfig`/`ruff`/analyzer severity, remove a rule from
  the lint config.
- Skip or delete the failing check: `--no-verify`, `[Skip]`/`it.skip`/`xit`,
  `@pytest.mark.skip`, commenting out a test or assertion, deleting the test.
- Edit the test/spec to match buggy behavior (see `tdd-first` — fix the code).

**The only legitimate suppression** is a *narrow, local, justified* one for a
true false-positive: scope it as tightly as the tool allows, add an inline
comment stating the reason, and surface it to the human for sign-off. A blanket
or file-level disable is never the move.

If a gate is genuinely wrong (a bad rule, a flaky test), say so explicitly and
propose changing the gate **deliberately** — don't route around it silently.
