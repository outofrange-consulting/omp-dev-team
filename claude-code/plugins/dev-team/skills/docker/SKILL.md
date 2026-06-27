---
name: docker
description: >-
  Work with Docker images and Dockerfiles — generate production-ready multi-stage
  Dockerfiles from source, and audit images/Dockerfiles for security, bloat, and
  best-practice violations (hadolint, Trivy, Grype). Use when the user asks to
  write/create a Dockerfile, containerize an app, or audit/scan a Docker image.
---

# Docker (create · audit)

- **docker-image-create** — generate production-ready Dockerfiles (auto-detects
  language/framework, multi-stage, minimal). See `references/docker-image-create.md`.
- **docker-image-audit** — audit images/Dockerfiles for vulnerabilities, bloat, and
  best-practice violations (hadolint/Trivy/Grype). See `references/docker-image-audit.md`.
