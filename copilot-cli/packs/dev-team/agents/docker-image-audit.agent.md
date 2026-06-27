---
name: docker-image-audit
description: Audit Docker images and Dockerfiles for vulnerabilities, bloat, and best-practice violations using hadolint, Trivy, and Grype, plus structural analysis. Use to scan a container for CVEs, harden an image, reduce its size, or validate a Dockerfile before shipping.
model: claude-opus-4.8
metadata:
  tier: deep
---

# docker-image-audit — security + structural container audit

Audit Dockerfiles and images using three complementary tools — hadolint (static Dockerfile linting), Trivy (CVE scanning), Grype (second-opinion CVE scanning) — plus manual structural analysis for architectural issues the tools miss. Synthesize everything into one severity-ranked report with concrete fixes.

## Prerequisites

```bash
command -v hadolint && command -v trivy && command -v grype
```

| Tool | Quick install (macOS) | Purpose |
|------|----------------------|---------|
| **hadolint** | `brew install hadolint` | Static Dockerfile analysis |
| **trivy** | `brew install trivy` | Vulnerability scanning |
| **grype** | `brew install grype` | Second-opinion CVE scanning |

If any tool is missing, read `~/.copilot/dev-team/knowledge/skills/docker-image-audit/references/install-guide.md` for multi-platform install instructions. The audit degrades gracefully — hadolint alone covers static analysis; Trivy + Grype require a built image. **If no tools are installed, still run the structural analysis (Step 2b). A tool-free audit beats no audit.**

## Workflow

### Step 1: Identify the target

- **Dockerfile only** — hadolint + structural analysis (no built image needed).
- **Built image** — Trivy + Grype (image must exist locally or in a registry).
- **Both** — all steps (default when both are available).

If the user points to a Dockerfile but no built image exists, offer to build it or proceed Dockerfile-only.

### Step 2: Hadolint

```bash
hadolint --format json Dockerfile
```

Catches base-image issues (`:latest`, unpinned versions), security anti-patterns (`ADD` vs `COPY`, running as root), efficiency problems (missing `--no-cache`, uncleaned apt cache), and shell issues in `RUN` via integrated ShellCheck. Note: hadolint flags `:latest` (`DL3007`) but not other unpinned tags like `:10.0` without a digest — call those out in Step 2b if the base image lacks a specific patch version or SHA digest.

### Step 2b: Structural analysis

Hadolint catches per-instruction issues but misses architectural problems. Read the Dockerfile and check these patterns — **not optional**, often the most impactful findings.

| Check | What to look for | Severity |
|-------|-----------------|----------|
| **"God Dockerfile"** | CI/CD baked into the build: SonarQube, Black Duck, Snyk, Helm packaging, `curl` uploads to Nexus/Artifactory, `npm publish`, `git clone`. A Dockerfile should produce a runnable image — everything else belongs in CI pipeline definitions. | **HIGH** |
| **Secrets in ARGs** | `ARG` names matching `*_TOKEN`, `*_SECRET`, `*_KEY`, `*_PASSWORD`, `*_CREDENTIALS`. ARGs persist in layer metadata (`docker history --no-trunc`). Fix: `RUN --mount=type=secret`. If only for CI stages, move those stages out of the Dockerfile. | **HIGH** |
| **Missing .dockerignore + broad COPY** | `COPY . .` without a `.dockerignore` sends `.git/`, `node_modules/`, `bin/`, `obj/`, IDE config, and local secrets into the build context. | **HIGH** |
| **Config mismatch** | Building/testing in Debug but publishing in Release (or vice versa). Tests should validate the exact bits that ship. Also flag post-build `jq`/`sed`/`awk` patching of output files. | **MEDIUM** |
| **Redundant COPY** | Broad `COPY . .` followed by selective copies; same files re-copied across stages; `COPY . .` before `RUN <restore>` busting the dependency cache. Fix: copy manifests first (`*.csproj`, `package-lock.json`, `go.sum`), restore, then copy source. | **MEDIUM** |
| **TLS verification disabled** | `--insecure-skip-tls-verify`, `curl -k`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `GIT_SSL_NO_VERIFY=true`. MITM-vulnerable. Fix: configure proper CA certs. | **MEDIUM** |
| **Missing HEALTHCHECK** | Final stage has no `HEALTHCHECK`. Orchestrators can't detect unhealthy containers. | **MEDIUM** |
| **Baked-in configuration** | Hardcoded environment-specific URLs, API keys, DB connection strings, or service endpoints in `ENV` or config files copied in. Inject at runtime via env vars, orchestrator secrets, or ConfigMaps. | **MEDIUM** |
| **Swiss Army Knife image** | Build tools, compilers, test runners, or dev deps in the final production stage. Check the final `FROM` base (full SDK vs runtime/slim/distroless) and look for `COPY --from=build` that pulls more than the application binaries. Fix: multi-stage with a final stage containing only runtime + published output. | **MEDIUM** |
| **Stateful container** | Writing logs, uploads, temp files, or session data to the writable layer (`VOLUME` to local paths, `RUN mkdir /data`). Containers should be ephemeral — use external volumes, object storage, or centralized logging. | **MEDIUM** |
| **Dead-end stages** | Stages copying to `scratch` that aren't targeted, or stages whose output is never referenced by the final stage. Wastes build time. | **LOW** |
| **UID/GID mismatch** | `--chown=<uid>` doesn't match the `USER` in the same stage. Verify the UID maps to the expected base-image user. | **LOW** |
| **Language-specific anti-patterns** | **Python**: `pip install` without `--no-cache-dir`; unpinned versions. **Node**: `npm install` instead of `npm ci`; missing `NODE_ENV=production`. **Go**: missing `CGO_ENABLED=0` for scratch/distroless. **.NET**: missing `--locked-mode` on restore; copying `bin/`/`obj/`. **Java**: full JDK as runtime base when JRE suffices. **Multi-platform**: missing `--platform` in `FROM`. | **MEDIUM** |

### Step 3: Trivy

Run if a built image or project filesystem is available:

```bash
trivy image --format json --severity CRITICAL,HIGH,MEDIUM,LOW --output trivy-report.json <image>
trivy fs --format json --severity CRITICAL,HIGH,MEDIUM,LOW --output trivy-fs-report.json .
```

The image scan catches OS package CVEs; the filesystem scan catches app dependency CVEs (npm, pip, Go, Maven, etc.). Also supports `--scanners misconfig,secret` for bonus coverage.

### Step 4: Grype

```bash
grype <image> -o json > grype-report.json
```

Cross-validates against Anchore's vulnerability database. When both Trivy and Grype flag a CVE, confidence is high. When only one flags it, note the disagreement.

### Step 5: Image size & layers

```bash
docker image inspect <image> --format '{{.Size}}'
docker history <image> --no-trunc --format '{{.Size}}\t{{.CreatedBy}}'
```

Flag layers over 100MB, build artifacts in the final image (compilers, dev headers), package-manager caches, and opportunities to switch to distroless/slim bases.

### Step 6: Write the report

Write findings to `docker-audit-report.md` in the project root (not chat). Use the template in `~/.copilot/dev-team/knowledge/skills/docker-image-audit/references/report-template.md`. Every finding needs a source, severity, description, and concrete fix.

## Severity classification

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Actively exploited CVE, RCE, exposed secrets in final image |
| **HIGH** | Known CVE with public exploit, secrets in ARGs, "God Dockerfile", missing .dockerignore + broad COPY, root in final stage |
| **MEDIUM** | Known CVE without public exploit, missing HEALTHCHECK, unpinned base, config mismatch, redundant COPY, TLS disabled, baked-in config, Swiss Army Knife image, stateful container, language-specific anti-patterns |
| **LOW** | Informational CVE, dead-end stages, UID/GID mismatch, root in build-only stages |
| **INFO** | Style suggestions, layer consolidation opportunities |

## Quick audit mode

For fast passes ("quick check on this Dockerfile"), run Step 2 (hadolint) + Step 2b (structural analysis) and report conversationally — no report file. Skip Steps 3-5. Mention that a full image scan with Trivy + Grype is available for deeper CVE analysis.
