# cc-dev-team — a Claude Code CLI marketplace

A port of the [omp-dev-team](../README.md) experience to the **Claude Code CLI**.
Six independent plugins and a global installer that sets up the `claude` CLI and
walks you through each plugin **and each external dependency** (ctx-wire, pup, the
ADO MCP, …) one at a time.

> **Upstream note.** The original [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team)
> (Bryan Finster) **is itself a native Claude Code project**. omp-dev-team ported it
> *to* Oh-My-Pi; this tree ports it *back* to Claude Code, so it re-adopts upstream's
> own conventions for gates/hooks (see [Upstream fidelity](#upstream-fidelity)).

| Plugin | What it does |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Agentic dev team** — orchestrator + 30 specialist/critic **subagents**, the `/specs → /plan → /build → /pr` workflow, a **blocking review gate** + advisory plan gate, a **SessionStart operating manual**, and a deterministic `/impl-verify` build+test gate. |
| **[`token-diet`](plugins/token-diet/)** | **Token reduction** — **ctx-wire** (`ctx-wire init claude` installs its hook), **codebase-memory** MCP (installed via its own Claude-Code-aware installer), a live **cache/cost statusline**, and the **caveman**/**yagni**/**codebase-memory**/**mcp-as-cli-skill-creator** skills. |
| **[`datadog`](plugins/datadog/)** | **Datadog observability** via the [`pup`](https://github.com/DataDog/pup) CLI. One broad skill drives pup; the installer sets up pup + auth and can run `pup skills install claude`. |
| **[`azure-devops`](plugins/azure-devops/)** | **Azure DevOps** via Microsoft's **official [`@azure-devops/mcp`](https://github.com/microsoft/azure-devops-mcp)** server — repos, PRs, pipelines, work items, wiki, test plans. Azure-CLI auth (`az login`); org set via plugin `userConfig`. |
| **[`cliproxy`](plugins/cliproxy/)** | **CLIProxyAPI provider** — route Claude Code through a [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) gateway (Anthropic-compatible OOB) via `ANTHROPIC_BASE_URL`. Config-only. |
| **[`copilot-preset`](plugins/copilot-preset/)** | **GitHub Copilot preset** — run on a Copilot license via the [`copilot-api`](https://github.com/ericc-ch/copilot-api) bridge + `ANTHROPIC_BASE_URL` (Claude Code can't use Copilot models natively). Config-only. |

## Quick start

```sh
bash claude-code/install.sh            # Linux/macOS   (-y for non-interactive)
#   pwsh -File claude-code/install.ps1  # Windows
```

The installer installs/updates the **Claude Code CLI** and **Node.js** (the
hooks/statusline/gate run on `node`), registers this marketplace
(`claude plugin marketplace add`), then asks about each plugin and dependency one
at a time. It configures `~/.claude/settings.json` by a **structural JSON merge**
— anything you've already set is preserved (no clobber; idempotent on re-run).

## Manual install

```sh
claude plugin marketplace add ./claude-code
claude plugin install dev-team@cc-dev-team
claude plugin install token-diet@cc-dev-team
claude plugin install datadog@cc-dev-team
claude plugin install azure-devops@cc-dev-team     # prompts for your ADO org
claude plugin install cliproxy@cc-dev-team
claude plugin install copilot-preset@cc-dev-team
```

External tools (per the dependency you want):

```sh
curl -fsSL https://ctx-wire.dev/install.sh | sh && ctx-wire init claude              # token-diet
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash   # token-diet (auto-wires Claude Code)
brew install datadog-labs/pack/pup                                                    # datadog
az login                                                                             # azure-devops
```

## How the OMP/upstream concepts map onto Claude Code

OMP's runtime **extension modules** (`pi.on(...)`, `pi.registerTool/Command/Provider`)
have no Claude Code equivalent, so each was re-expressed in a native idiom:

| Concept | Claude Code equivalent |
|---|---|
| `agents/*.md` (OMP tiers `pi/smol`/`claude-sonnet-4-6`/`claude-opus-4-8`) | Subagents with `model: haiku\|sonnet\|opus` + `effort:` (from `thinking-level`) |
| `commands/*.md`, `skills/*/SKILL.md` (`skill://`, `allowed-tools`) | Same files; tools remapped (`read→Read`, `bash→Bash`, `search→Grep`, `find→Glob`, `task→Task`), `skill://x` rewritten |
| OMP rules `alwaysApply: true` + `canary.ts` | **SessionStart hook** injects them as `additionalContext` and checks the `DT-CANARY-7Q2F` sentinel |
| `review-gate.ts` | **Blocking** PreToolUse `Bash` hook (`gate.mjs precheck`) — denies `git commit` unless `.review-passed` (repo root) matches the staged-diff hash; edits invalidate it; PostToolUse clears it after commit. **Matches upstream.** |
| `plan-gate.ts` | **Advisory** PreToolUse `Write\|Edit` hook (`ask`); state in `.dev-team/state.json`. Upstream enforces plan approval in the `/build` skill — this is the lighter variant. |
| `/scope`, `/plan-approve`, `/review-approve`, `/impl-verify` | Slash commands driving the `devteam-gate` / `devteam-impl-verify` CLIs in `bin/` |
| `path-guard.ts` / `destructive-guard.ts` | **Native `permissions`** in `settings.json` (`deny` secrets, `ask` `rm -rf`/force-push) — same layer upstream uses |
| `cache-meter.ts` | **statusLine** script (`statusline/cache-meter.mjs`) |
| `read-dedup`/`context-dedup`/`context-compress` | Dropped (no message-rewrite hook); Claude Code's native compaction + ctx-wire cover it |
| ctx-wire | `ctx-wire init claude` (installs its Claude Code hook), not bare PATH shims |
| codebase-memory-mcp | Its own installer auto-detects Claude Code (writes `.mcp.json` + 4 skills + a discovery hook) — so token-diet does **not** bundle a duplicate MCP |
| pup | `pup skills install claude` + the `datadog` umbrella skill |
| OMP `ado` tool (registerTool) | The **official `@azure-devops/mcp`** server via the plugin's `.mcp.json` (org from `userConfig`) |
| OMP `cliproxy`/`copilot-preset` (models.yml provider) | Native `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` redirection — wired by the installer into `settings.json` `env` |
| `~/.omp/agent/config.yml` (YAML append-merge) | `~/.claude/settings.json` (**structural JSON merge** — fixes the OMP YAML-corruption flaw) |

## Upstream fidelity

Checked against `bdfinst/agentic-dev-team` (`plugins/dev-team/settings.json` +
`hooks/`). Where this port lands:

- **Review gate — matches.** Upstream blocks `git commit` with a PreToolUse `Bash`
  hook that denies unless a **content-hashed `.review-passed`** at repo root matches
  the staged files; any later edit invalidates it. This port reproduces that exactly
  (blocking `deny`, repo-root `.review-passed`, edit-invalidation, post-commit cleanup,
  `--no-verify` escape hatch).
- **Native `permissions.deny` for hard safety — matches.**
- **Deterministic build/test gate — matches** (`/impl-verify`).
- **Plan gate — variant.** Upstream enforces it inside the `/build` skill (the plan
  file's `Status: approved`); this port adds a lighter advisory PreToolUse hook. Both
  keep the same human checkpoint.
- **Models — variant.** Upstream uses `effort:` bands + an `agent-model-resolve` hook
  + `model-ladder.json`; this port uses native `model:` frontmatter (simpler, works
  OOB). `effort:` is preserved on every agent for an easy switch later.
- **Workflow `/specs → /plan → /build → /pr` — matches.** (Upstream ships these as
  skills only; this port keeps thin top-level `commands/` launchers too.)

## Honesty note on the gates

OMP's review ([REVIEW.md](../REVIEW.md)) found the OMP guards to be *security
theater*. This port avoids that: hard file/command safety is Claude Code's native
permission engine; the **review gate is genuinely blocking and content-bound**
(an agent rewriting `.review-passed` still can't approve a *different* diff); the
plan gate is honestly labelled advisory.

## Regenerating the ported content

The bulk agents/commands/skills are mechanically ported from `../plugins` by
[`scripts/port-from-omp.mjs`](scripts/port-from-omp.mjs) (re-run after upstream OMP
changes). The hooks, gate CLI, statusline, manifests, the three config/MCP plugins,
and the installers are hand-authored.

## Not a 1:1 of OMP

`copilot-preset` and `cliproxy` are config-only on Claude Code (native
`ANTHROPIC_BASE_URL` redirection, no custom provider code), and `azure-devops` uses
Microsoft's official MCP instead of a rebuilt `ado` tool. OMP's original versions
remain under [`../plugins`](../plugins).
