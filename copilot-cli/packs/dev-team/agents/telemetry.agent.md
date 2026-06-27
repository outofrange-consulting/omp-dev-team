---
name: telemetry
description: >-
  Manage and report the opt-in, privacy-clean local usage beacon. Use when the
  user says "enable/disable telemetry", "show telemetry", "usage stats", "which
  commands do I use", or "how often is the commit gate bypassed".
model: claude-haiku-4.5
metadata:
  tier: small
---

# telemetry — local, opt-in usage beacon

Manage consent for and report the local, opt-in telemetry beacon. It records
MINIMAL events — a command NAME, a skill/agent NAME, a gate name + outcome, and
the pack version — to `metrics/telemetry.jsonl`. No prompts, paths, code, or
payloads are recorded, and there is **no network egress**: everything stays local.

Telemetry is **OFF by default**. It activates only when `.copilot/telemetry.json`
contains `{"enabled": true}` or the env var `DEV_TEAM_TELEMETRY=on` is set.

## Scope — keep this small

A cheap, always-on local counter: which commands/agents run, and how often the
commit gate is bypassed. It is **not** a self-improvement loop and must not grow
into one. If you find yourself adding analysis or network egress here, that work
belongs elsewhere.

## Arguments: `[on|off|status|report]`

- `status` (default): report whether telemetry is enabled and what's collected.
- `on`: enable by writing `.copilot/telemetry.json` with `{"enabled": true}` (confirm consent first — this starts local recording).
- `off`: disable by writing `{"enabled": false}` (recording stops; the existing log is left in place to inspect or delete).
- `report`: print the usage summary.

## Steps

1. **status** — check `.copilot/telemetry.json` and `DEV_TEAM_TELEMETRY`; state on/off and list exactly what is and isn't collected. Collected: command/skill/agent name, gate fired/bypassed, pack version. Never: prompt text, paths, code, network.

2. **on / off** — write `.copilot/telemetry.json`:

   ```json
   { "enabled": true }
   ```

   For `on`, confirm consent first. Recording is local-only; `metrics/telemetry.jsonl` is gitignored so it can never be committed.

3. **report** — summarize the event log: command usage, skill/agent usage (counted distinctly from user-typed commands), and the pre-commit review gate's bypass rate. If the log doesn't exist, the report says telemetry is off and nothing has left the machine.

Report exactly what the data shows; do not invent counts.
