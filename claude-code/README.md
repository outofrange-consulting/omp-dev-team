# cc-dev-team — a Claude Code CLI marketplace

A port of the [omp-dev-team](../README.md) experience to the **Claude Code CLI**.
Three independent plugins, a global installer that sets up the `claude` CLI and
walks you through each plugin **and each external dependency** (ctx-wire, pup, …).

| Plugin | What it does |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Agentic dev team** — orchestrator + 30 specialist/critic **subagents**, the `/specs → /plan → /build → /pr` workflow, an **advisory** plan/review gate (PreToolUse hooks; state kept outside the repo), a **SessionStart operating manual**, and a deterministic `/impl-verify` build+test gate. Port of [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team). |
| **[`token-diet`](plugins/token-diet/)** | **Aggressive token reduction** — **ctx-wire** (transparent command-output compression + secret scrub via PATH shims), **codebase-memory** MCP (symbol/call-graph queries instead of grep+read), a live **cache/cost statusline**, and the **caveman**/**yagni**/**codebase-memory**/**mcp-as-cli-skill-creator** skills. |
| **[`datadog`](plugins/datadog/)** | **Datadog observability** via the Datadog [`pup`](https://github.com/DataDog/pup) CLI (logs, metrics, APM, monitors, incidents, dashboards, SLOs, RUM, security, CI test visibility, LLM observability). One broad `datadog` skill drives pup; installer sets up pup + auth. |

## Quick start

```sh
# from the repo root
bash claude-code/install.sh            # Linux/macOS   (-y for non-interactive)
#   pwsh -File claude-code/install.ps1  # Windows
```

The installer: installs/updates the **Claude Code CLI** (`https://claude.ai/install.sh`)
and **Node.js** (the hooks/statusline/gate run on `node`), registers this
marketplace (`claude plugin marketplace add`), then asks about each plugin and
its dependencies one at a time. It configures `~/.claude/settings.json` by a
**structural JSON merge** — anything you've already set is preserved (no clobber).

## Manual install

```sh
claude plugin marketplace add ./claude-code
claude plugin install dev-team@cc-dev-team
claude plugin install token-diet@cc-dev-team
claude plugin install datadog@cc-dev-team
```

External tools (only needed for the dependency you want):

```sh
curl -fsSL https://ctx-wire.dev/install.sh | sh && ctx-wire shims install           # token-diet
curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash   # token-diet
brew install datadog-labs/pack/pup   # or a GitHub release tarball                  # datadog
```

## How the OMP concepts map onto Claude Code

This is the heart of the port — OMP's runtime **extension modules** (`pi.on(...)`,
`pi.registerTool/Command/Provider`) have no Claude Code equivalent, so each was
re-expressed in a native Claude Code idiom:

| OMP concept | Claude Code equivalent |
|---|---|
| `agents/*.md` (tiers `pi/smol`, `claude-sonnet-4-6`, `claude-opus-4-8`) | Subagents with `model: haiku\|sonnet\|opus`, `effort:` from `thinking-level` |
| `commands/*.md`, `skills/*/SKILL.md` (`skill://` refs, `allowed-tools`) | Same files, tool names mapped (`read→Read`, `bash→Bash`, `search→Grep`, `find→Glob`, `task→Task`), `skill://x` rewritten |
| `rules/*.md` with `alwaysApply: true` | **SessionStart hook** injects them as `additionalContext` |
| `canary.ts` (verify manual loaded) | Same SessionStart hook checks the `DT-CANARY-7Q2F` sentinel |
| `plan-gate.ts` / `review-gate.ts` (block writes/commits) | **PreToolUse hook** (`gate.mjs precheck`) returns an `ask` decision; state in `${CLAUDE_PLUGIN_DATA}` (not agent-writable) |
| `/scope`, `/plan-approve`, `/review-approve`, `/impl-verify` (extension commands) | Slash commands driving the `devteam-gate` / `devteam-impl-verify` CLIs in `bin/` |
| `path-guard.ts` / `destructive-guard.ts` | **Native `permissions`** in `settings.json` (`deny` for secrets, `ask` for `rm -rf`/force-push) — a real barrier, not advisory |
| `model-routing.ts` (runtime tier enforcement) | Dropped — Claude Code picks a subagent's model from its frontmatter; tiers live there |
| `cache-meter.ts` (footer statusline) | **statusLine** script (`statusline/cache-meter.mjs`) |
| `read-dedup` / `context-dedup` / `context-compress` | Not portable (no message-rewrite hook); Claude Code's native compaction + ctx-wire cover most of it |
| ctx-wire, codebase-memory-mcp, pup | Unchanged — external binaries; ctx-wire via PATH shims, codebase-memory via the plugin's `.mcp.json`, pup via the `datadog` skill |
| `~/.omp/agent/config.yml` (YAML append-merge) | `~/.claude/settings.json` (**structural JSON merge** — fixes the OMP YAML-corruption flaw) |

**Not ported** (no clean Claude Code analog): `copilot-preset` (Claude Code
doesn't route through GitHub Copilot models), `cliproxy` (OpenAI-compatible
gateway vs. Anthropic format), and `azure-devops-fs`'s native `ado` tool (would
need re-building as an MCP server). OMP's versions stay in [`../plugins`](../plugins).

## Honesty note on the gates

OMP's review ([REVIEW.md](../REVIEW.md)) found the OMP guards to be *security
theater* — trivially bypassable, with state the agent could rewrite. This port
**does not repeat that**: hard file/command safety is delegated to Claude Code's
own permission engine (`deny`/`ask`), and the plan/review gates are honestly
labelled **advisory** (they `ask`, they don't hard-block) with state kept
**outside the repo** under the plugin data dir.

## Regenerating the ported content

The bulk agents/commands/skills are mechanically ported from `../plugins` by
[`scripts/port-from-omp.mjs`](scripts/port-from-omp.mjs). Re-run after upstream
OMP changes: `node claude-code/scripts/port-from-omp.mjs`. The hooks, statusline,
MCP config, manifests, and installers are hand-authored (the non-mechanical part).
