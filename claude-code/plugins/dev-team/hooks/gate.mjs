#!/usr/bin/env node
// gate.mjs — dev-team plan/review gate for Claude Code.
//
// Honest framing (cf. REVIEW.md): this is an ADVISORY workflow gate, not a
// security barrier. It nudges the agent through scope -> plan -> build -> review
// by returning a PreToolUse `ask` decision (the human still confirms). Hard
// file/command safety is left to Claude Code's native permissions (deny/ask in
// settings.json) — see the installer.
//
// Crucially, gate state lives OUTSIDE the repo, under the plugin data dir
// (or ~/.claude/dev-team-state), keyed by git-repo root — so the agent it
// constrains cannot rewrite the state file from within the workspace.
//
// Usage (also exposed as `devteam-gate` on PATH via bin/):
//   gate.mjs precheck         # PreToolUse hook: reads hook JSON on stdin
//   gate.mjs scope [--trivial|--complex]
//   gate.mjs plan-approve     # clears the plan gate
//   gate.mjs review-approve   # clears the review gate for the current staged diff
//   gate.mjs plan-reset | status | freeze <glob> | unfreeze | careful <on|off>
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { createHash } from "node:crypto";

function sh(cmd, args) {
  try { return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); }
  catch { return ""; }
}
function repoRoot() { return sh("git", ["rev-parse", "--show-toplevel"]) || process.cwd(); }
function stateDir() {
  const base = process.env.CLAUDE_PLUGIN_DATA || join(homedir(), ".claude", "dev-team-state");
  const key = createHash("sha256").update(repoRoot()).digest("hex").slice(0, 16);
  const d = join(base, key);
  mkdirSync(d, { recursive: true });
  return d;
}
function statePath(n) { return join(stateDir(), `${n}.json`); }
function readState(n) { try { return JSON.parse(readFileSync(statePath(n), "utf8")); } catch { return {}; } }
function writeState(n, o) { writeFileSync(statePath(n), JSON.stringify(o, null, 2)); }
function now() { return new Date().toISOString(); }

// A "gated source" file = production code, not tests/specs/docs/config.
const SRC_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|py|cs|go|rs|java|rb|php|kt|swift|scala|c|cc|cpp|h|hpp|vue|svelte)$/i;
const NON_GATED = /(\.(test|spec)\.|[._]test\.|\/tests?\/|\/__tests__\/|\.feature$|\.md$|\.json$|\.ya?ml$|\.txt$)/i;
function isGatedSource(p) { return !!p && SRC_EXT.test(p) && !NON_GATED.test(p); }

function pathsFromInput(tool, input) {
  if (!input) return [];
  if (tool === "Write" || tool === "Edit") return [input.file_path || input.path].filter(Boolean);
  return [];
}

function ask(reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: reason },
  }));
  process.exit(0);
}
function pass() { process.exit(0); }

function precheck() {
  let raw = "";
  try { raw = readFileSync(0, "utf8"); } catch {}
  let ev = {}; try { ev = JSON.parse(raw || "{}"); } catch {}
  const tool = ev.tool || ev.tool_name || "";
  const input = ev.tool_input || ev.toolInput || {};
  const careful = readState("careful").on === true; // reserved for future hard-block mode

  // review gate: git commit before /review-approve
  if (tool === "Bash") {
    const cmd = String(input.command || "");
    if (/\bgit\s+commit\b/.test(cmd) && !/--no-verify\b/.test(cmd)) {
      const rg = readState("review-gate");
      if (rg.approvedDiff !== stagedDiffHash()) {
        ask("review-gate: staged changes haven't been review-approved. Run /code-review, then /review-approve (or add --no-verify to bypass). Advisory only — confirm to proceed.");
      }
    }
    return pass();
  }

  // plan gate: editing production source before the plan is approved
  if (tool === "Write" || tool === "Edit") {
    const pg = readState("plan-gate");
    const stage = pg.stage || "needs-scope";
    if (stage === "plan-approved" || stage === "trivial") return pass();
    const gated = pathsFromInput(tool, input).some(isGatedSource);
    if (gated) {
      ask(`plan-gate: this task isn't scoped/planned yet (stage="${stage}"). Run /scope then /plan-approve before editing production source — or /scope --trivial for a one-liner. Advisory only — confirm to proceed.`);
    }
  }
  return pass();
}

function stagedDiffHash() {
  const diff = sh("git", ["diff", "--cached"]);
  return diff ? createHash("sha256").update(diff).digest("hex").slice(0, 16) : "empty";
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  switch (cmd) {
    case "precheck": return precheck();
    case "scope": {
      const size = rest.includes("--complex") ? "complex" : rest.includes("--trivial") ? "trivial" : "standard";
      const stage = size === "trivial" ? "trivial" : "needs-plan";
      writeState("plan-gate", { stage, size, at: now() });
      console.log(`scoped: size=${size}, stage=${stage}${stage === "needs-plan" ? " (run /plan, then /plan-approve)" : " (trivial — edits allowed)"}`);
      break;
    }
    case "plan-approve": {
      const pg = readState("plan-gate");
      writeState("plan-gate", { ...pg, stage: "plan-approved", at: now() });
      console.log("plan-gate: approved — build phase unlocked.");
      break;
    }
    case "plan-reset": writeState("plan-gate", { stage: "needs-scope", at: now() }); console.log("plan-gate: reset."); break;
    case "review-approve":
      writeState("review-gate", { approvedDiff: stagedDiffHash(), at: now() });
      console.log("review-gate: current staged diff approved — commit unlocked.");
      break;
    case "careful": {
      const on = rest[0] === "on";
      writeState("careful", { on, at: now() });
      console.log(`careful mode: ${on ? "ON" : "OFF"}`);
      break;
    }
    case "status": {
      console.log(JSON.stringify({ planGate: readState("plan-gate"), reviewGate: readState("review-gate"), careful: readState("careful"), stateDir: stateDir() }, null, 2));
      break;
    }
    default:
      console.log("usage: gate.mjs precheck|scope [--trivial|--complex]|plan-approve|plan-reset|review-approve|careful <on|off>|status");
      process.exit(cmd ? 2 : 0);
  }
}
main();
