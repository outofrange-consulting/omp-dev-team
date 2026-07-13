#!/usr/bin/env node
// merge-skills.mjs — consolidate closely-related dev-team skills into umbrella
// skills to cut always-on frontmatter context (Claude Code loads every skill's
// `description` on every request). Member bodies are PRESERVED as references/<m>.md
// under the umbrella (progressive disclosure — loaded only when the skill fires).
//
// ABSORB: fold members into an EXISTING umbrella skill (keep its SKILL.md).
// NEW:    create a NEW umbrella SKILL.md and fold members under it.
// DROP:   remove a pure-alias skill (its slash command stays).
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync, cpSync, readdirSync } from "node:fs";
import { join } from "node:path";

const SK = join(process.cwd(), "claude-code/plugins/dev-team/skills");
const body = (p) => { const t = readFileSync(p, "utf8"); if (!t.startsWith("---")) return t; const e = t.indexOf("\n---", 3); return e === -1 ? t : t.slice(e + 4).replace(/^\n+/, ""); };
const titleOf = (t) => (t.split(/^description:/m)[1] || "").split("\n")[0].replace(/[>|-]/g, "").trim();

function toReference(umbrella, member) {
  const memDir = join(SK, member);
  const refDir = join(SK, umbrella, "references");
  mkdirSync(refDir, { recursive: true });
  writeFileSync(join(refDir, `${member}.md`), `# ${member}\n\n${body(join(memDir, "SKILL.md"))}`);
  // carry every supporting file the member had (references/, scripts/, etc.) so
  // nothing is lost — flattened into the umbrella's references/ dir.
  for (const entry of readdirSync(memDir, { withFileTypes: true })) {
    if (entry.name === "SKILL.md") continue;
    cpSync(join(memDir, entry.name), join(refDir, entry.name), { recursive: true });
  }
  rmSync(memDir, { recursive: true, force: true });
}

const ABSORB = {
  "exploratory-testing": ["explore"],
  "semantic-duplication-scan": ["semantic-scan"],
  "performance-benchmark": ["benchmark"],
  "static-analysis-integration": ["semgrep-analyze"],
  "domain-driven-design": ["ubiquitous-language"],
};

const NEW = {
  "scope-control": {
    members: ["careful", "freeze", "unfreeze", "guard"],
    fm: `name: scope-control
description: >-
  Limit what the agent may touch this session — careful mode (block destructive
  commands like rm -rf / force-push / DROP TABLE) and freeze/guard (scope-lock
  editing to a glob). Use when the user says "careful mode", "freeze", "unfreeze",
  "guard", "lock editing", "protect production", or wants a safety leash.`,
    intro: `# Scope control (careful · freeze · guard)

Session safety leashes. **Note for the Claude Code port:** the hard enforcement
lives in two places — careful mode is tracked by the dev-team gate
(\`devteam-gate careful on|off\`), and destructive-command / secret safety is
enforced by Claude Code's native \`permissions\` (deny/ask in settings.json). The
\`freeze\`/\`unfreeze\`/\`guard\` glob-locks are **advisory** here (there is no freeze
hook); honor them as working agreements. See \`references/\` for each mode.`,
  },
  "task-metrics": {
    members: ["telemetry", "cost-report", "performance-metrics"],
    fm: `name: task-metrics
description: >-
  Record and report task accounting — token/dollar spend per agent (cost), the
  opt-in usage telemetry beacon, and end-of-task completion metrics (tokens, cost,
  agents, rework, hallucinations) to metrics/. Use when the user asks "how much did
  that cost", "show telemetry", "enable/disable telemetry", or to log task metrics.`,
    intro: `# Task metrics (cost · telemetry · completion logging)

All task-accounting outputs in one place. Pick the sub-capability in \`references/\`:
- **cost-report** — actual token spend + dollar cost per agent and total; flag regressions.
- **telemetry** — manage/report the opt-in, privacy-clean usage beacon.
- **performance-metrics** — log per-task completion data (tokens, cost, agents, rework, hallucinations) to metrics/.`,
  },
  "docker": {
    members: ["docker-image-audit", "docker-image-create"],
    fm: `name: docker
description: >-
  Work with Docker images and Dockerfiles — generate production-ready multi-stage
  Dockerfiles from source, and audit images/Dockerfiles for security, bloat, and
  best-practice violations (hadolint, Trivy, Grype). Use when the user asks to
  write/create a Dockerfile, containerize an app, or audit/scan a Docker image.`,
    intro: `# Docker (create · audit)

- **docker-image-create** — generate production-ready Dockerfiles (auto-detects
  language/framework, multi-stage, minimal). See \`references/docker-image-create.md\`.
- **docker-image-audit** — audit images/Dockerfiles for vulnerabilities, bloat, and
  best-practice violations (hadolint/Trivy/Grype). See \`references/docker-image-audit.md\`.`,
  },
  "context-management": {
    members: ["context-loading-protocol", "context-summarization"],
    fm: `name: context-management
description: >-
  Manage the working context window — at task start, select the minimum viable set
  of agents/skills to load (context-loading-protocol); mid-task, compress history
  when utilization gets high (context-summarization). Use to decide what to load or
  when output quality drops / context fills up.`,
    intro: `# Context management (load minimal · summarize)

- **context-loading-protocol** — decide which agents/skills to load for a task;
  compute the minimum viable context. See \`references/context-loading-protocol.md\`.
- **context-summarization** — compress conversation history when context utilization
  is high. See \`references/context-summarization.md\`.`,
  },
  "design-techniques": {
    members: ["design-interrogation", "design-it-twice"],
    fm: `name: design-techniques
description: >-
  Pressure-test a design before building — interrogate a plan/spec to surface
  unresolved decisions, hidden assumptions, and edge cases (design-interrogation),
  or generate multiple radically different designs in parallel and synthesize the
  best (design-it-twice, Ousterhout). Use when refining a design or choosing an approach.`,
    intro: `# Design techniques (interrogate · design it twice)

- **design-interrogation** — relentlessly interview the user about a plan/design to
  surface unresolved decisions and edge cases. See \`references/design-interrogation.md\`.
- **design-it-twice** — generate multiple radically different designs via parallel
  sub-agents, then compare and synthesize. See \`references/design-it-twice.md\`.`,
  },
};

const DROP = ["review"]; // pure alias of code-review; the /review command stays

let removed = 0;
for (const [umb, members] of Object.entries(ABSORB)) {
  if (!existsSync(join(SK, umb, "SKILL.md"))) { console.log(`SKIP absorb ${umb} (missing)`); continue; }
  for (const m of members) { if (existsSync(join(SK, m))) { toReference(umb, m); removed++; console.log(`absorb: ${m} -> ${umb}/references`); } }
}
for (const [umb, cfg] of Object.entries(NEW)) {
  mkdirSync(join(SK, umb), { recursive: true });
  for (const m of cfg.members) { if (existsSync(join(SK, m))) { toReference(umb, m); removed++; console.log(`new: ${m} -> ${umb}/references`); } }
  writeFileSync(join(SK, umb, "SKILL.md"), `---\n${cfg.fm}\n---\n\n${cfg.intro}\n`);
  console.log(`created umbrella: ${umb}`);
}
for (const d of DROP) { if (existsSync(join(SK, d))) { rmSync(join(SK, d), { recursive: true, force: true }); removed++; console.log(`drop: ${d}`); } }

console.log(`\nRemoved ${removed} top-level skill descriptions.`);
