# azure-devops-fs

> 🌐 **English** · [Français](README.fr.md)

**Azure DevOps as a filesystem for [Oh-My-Pi](https://github.com/can1357/oh-my-pi).**
The ADO analog of OMP's "GitHub as a filesystem" (`pr://` / `issue://` + the
`github` tool). Standalone — depends on no other plugin.

Since OMP's `xxx://` internal-URL schemes are registered in the core (not
pluggable), this plugin delivers the same model through one custom tool, `ado`,
that makes paths/refs first-class and understands `ado://` / `adopr://` URIs.

## Capabilities

- **Read** (cached in `~/.omp/cache/ado-cache.db`): `repo_view`, `repo_ls`,
  `repo_read`, `pr_view` (+threads), `pr_list`, `pr_files`, `pr_diff`,
  `work_item`, `search_code`.
- **Write**: `pr_create`, `pr_checkout` (clones the PR branch into
  `~/.omp/wt/...`), `pr_push`, `pr_comment`, `pr_vote`, `pr_abandon`,
  `pipeline_watch`, `work_item` create.
- **URIs**: `ado://{org}/{project}/{repo}/{path}@{ref}`,
  `adopr://{org}/{project}/{repo}/{id}[/diff[/path]]` (org/project default from env).
- **Commands**: `/ado`, `/ado-pr`, `/ado-review`, `/ado-pipeline`.
- **Skill**: `skill://azure-devops-fs`. **Rule**: PAT safety.

## Setup

```sh
omp plugin install azure-devops-fs@omp-dev-team
bash plugins/azure-devops-fs/install.sh     # ensures Node + prompts for org/project/PAT
```

The installer (interactive) asks for your org/project/**PAT** and persists them
(org/project to your shell profile; the PAT to `~/.omp/secrets.env`, chmod 600,
sourced from your profile). To set them by hand instead:

```sh
export AZURE_DEVOPS_ORG=your-org
export AZURE_DEVOPS_PROJECT=your-project    # optional default
export AZURE_DEVOPS_PAT=xxxxxxxx            # Code R/W, PR R/W (+ Build R for pipelines)
```

## Design notes

- Auth is injected per-request (REST header; git `http.extraheader`) — the PAT is
  never written to disk or remote URLs.
- Reads are cached ~120s, scoped by a PAT fingerprint (`OMP_ADO_CACHE=0` to
  disable).
- Destructive ops (`pr_abandon`, `pr_vote reject`, force push) require
  confirmation (UI prompt, or `confirm: true` headless).
- `pr_diff` reconstructs a unified diff via `git diff --no-index` on the base vs
  source blobs (ADO has no single unified-diff endpoint).

## Optional MCP complement

`.mcp.json` ships the official Microsoft `@azure-devops/mcp` server (disabled by
default; set `enabled: true`). The native `ado` tool adds what the MCP server
does not: the `ado://` filesystem model, a read cache, PR worktrees, and the
`/ado-review` flow.

See [`knowledge/ado-api-reference.md`](knowledge/ado-api-reference.md) for the
op → REST mapping.
