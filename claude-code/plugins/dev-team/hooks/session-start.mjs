#!/usr/bin/env node
// session-start.mjs — dev-team SessionStart hook.
// OMP shipped an always-on "operating manual" rule (alwaysApply: true) plus a
// canary extension that verified the manual was actually loaded. Claude Code has
// no rule-glob engine, so we inject the always-on rules as `additionalContext`
// here, and fold the canary into the same hook (warn if the sentinel is missing).
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = process.env.CLAUDE_PLUGIN_ROOT || join(import.meta.dirname, "..");
const RULES = join(ROOT, "rules");
const SENTINEL = "DT-CANARY-7Q2F";

// Always-on rules: the operating manual + the universal engineering guardrails.
// Glob-scoped domain rules (domain-backend/frontend/infra) stay on disk and are
// surfaced by the relevant skills/agents rather than always loaded.
const ALWAYS = [
  "dev-team-operating-manual.md",
  "output-discipline.md",
  "tests-required.md",
  "no-disable-analyzers.md",
  "source-of-truth.md",
];

function stripFrontmatter(t) {
  if (!t.startsWith("---")) return t;
  const end = t.indexOf("\n---", 3);
  return end === -1 ? t : t.slice(end + 4).replace(/^\n+/, "");
}

let parts = [];
let canaryOk = false;
for (const f of ALWAYS) {
  const p = join(RULES, f);
  if (!existsSync(p)) continue;
  const raw = readFileSync(p, "utf8");
  if (raw.includes(SENTINEL)) canaryOk = true;
  parts.push(stripFrontmatter(raw).trim());
}

const out = {
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext:
      "# Dev-Team operating rules (always on)\n\n" +
      parts.join("\n\n---\n\n") +
      "\n\nWorkflow: /specs → /plan → /plan-approve → /build → /code-review → /review-approve → /pr. " +
      "Use /scope first; the plan/review gates are advisory (they ask for confirmation, they don't hard-block).",
  },
};
if (!canaryOk) {
  out.systemMessage =
    "⚠ dev-team: operating-manual canary missing — the always-on rules may not have loaded. Reinstall the plugin or check rules/dev-team-operating-manual.md.";
}
process.stdout.write(JSON.stringify(out));
