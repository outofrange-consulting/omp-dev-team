#!/usr/bin/env node
// gate.mjs — dev-team plan/review gate for Claude Code.
//
// Faithful to upstream bdfinst/agentic-dev-team (which IS a native Claude Code
// project), with the two gates it actually enforces:
//
//   • REVIEW GATE — BLOCKING. A PreToolUse `Bash` check denies `git commit`
//     unless `.review-passed` (repo root) holds the content-hash of the CURRENT
//     staged diff. `/review-approve` writes that hash; ANY later edit changes the
//     staged hash and silently invalidates the approval (upstream's key trick).
//     `--no-verify` is the logged escape hatch. State is in-repo and content-bound,
//     so an agent re-writing the file can't fake approval for different content.
//
//   • PLAN GATE — ADVISORY. A PreToolUse `Write|Edit` check returns `ask` (not a
//     hard block) when production source is edited before the task is scoped/
//     planned. Upstream enforces plan approval inside the /build skill (the plan
//     file's `Status: approved` line); this hook is the lighter advisory nudge.
//
// Hard file/command safety (secrets, rm -rf, force-push) is delegated to Claude
// Code's native settings.json `permissions.deny`/`ask` — same layer upstream uses.
//
// Also exposed as `devteam-gate` on PATH (bin/). Subcommands:
//   precheck | scope [--trivial|--complex] | plan-approve | plan-reset
//   review-approve | review-clear | careful <on|off> | status
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { join } from "node:path";
import { createHash } from "node:crypto";

function sh(cmd, args) {
  try { return execFileSync(cmd, args, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim(); }
  catch { return ""; }
}
function repoRoot() { return sh("git", ["rev-parse", "--show-toplevel"]) || process.cwd(); }
function reviewFile() { return join(repoRoot(), ".review-passed"); }
function stateFile() {
  const d = join(repoRoot(), ".dev-team");
  mkdirSync(d, { recursive: true });
  return join(d, "state.json");
}
function readState() { try { return JSON.parse(readFileSync(stateFile(), "utf8")); } catch { return {}; } }
function writeState(o) { writeFileSync(stateFile(), JSON.stringify(o, null, 2)); }
function now() { return new Date().toISOString(); }
function stagedHash() {
  const diff = sh("git", ["diff", "--cached"]);
  return diff ? createHash("sha256").update(diff).digest("hex").slice(0, 16) : "empty";
}

const SRC_EXT = /\.(ts|tsx|js|jsx|mjs|cjs|py|cs|go|rs|java|rb|php|kt|swift|scala|c|cc|cpp|h|hpp|vue|svelte)$/i;
const NON_GATED = /(\.(test|spec)\.|[._]test\.|\/tests?\/|\/__tests__\/|\.feature$|\.md$|\.json$|\.ya?ml$|\.txt$)/i;
const isGatedSource = (p) => !!p && SRC_EXT.test(p) && !NON_GATED.test(p);
const pathsFromInput = (tool, input) =>
  (tool === "Write" || tool === "Edit") && input ? [input.file_path || input.path].filter(Boolean) : [];

function emit(decision, reason) {
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: decision, permissionDecisionReason: reason },
  }));
  process.exit(0);
}
const pass = () => process.exit(0);

function precheck() {
  let ev = {}; try { ev = JSON.parse(readFileSync(0, "utf8") || "{}"); } catch {}
  const tool = ev.tool || ev.tool_name || "";
  const input = ev.tool_input || ev.toolInput || {};

  // REVIEW GATE (blocking) — git commit must match an approved staged hash.
  if (tool === "Bash") {
    const cmd = String(input.command || "");
    if (/\bgit\s+commit\b/.test(cmd) && !/--no-verify\b/.test(cmd)) {
      const want = stagedHash();
      const have = existsSync(reviewFile()) ? readFileSync(reviewFile(), "utf8").trim() : "";
      if (have !== want || want === "empty") {
        emit("deny",
          `review-gate (blocking): the staged changes are not review-approved. Run /code-review, then /review-approve to approve THIS staged diff. ` +
          `(Any edit after approval invalidates it.) Bypass with --no-verify if you must.`);
      }
    }
    return pass();
  }

  // PLAN GATE (advisory) — editing production source before scope/plan.
  if (tool === "Write" || tool === "Edit") {
    const pg = readState().planGate || {};
    const stage = pg.stage || "needs-scope";
    if (stage === "plan-approved" || stage === "trivial") return pass();
    if (pathsFromInput(tool, input).some(isGatedSource)) {
      emit("ask",
        `plan-gate (advisory): task isn't scoped/planned yet (stage="${stage}"). Run /scope then /plan-approve before editing production source — or /scope --trivial for a one-liner. Confirm to proceed.`);
    }
  }
  return pass();
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const st = readState();
  switch (cmd) {
    case "precheck": return precheck();
    case "postcommit": {
      // PostToolUse Bash: a successful `git commit` consumes the approval.
      let ev = {}; try { ev = JSON.parse(readFileSync(0, "utf8") || "{}"); } catch {}
      const c = String((ev.tool_input || {}).command || "");
      if (/\bgit\s+commit\b/.test(c) && existsSync(reviewFile())) rmSync(reviewFile());
      process.exit(0);
    }
    case "scope": {
      const size = rest.includes("--complex") ? "complex" : rest.includes("--trivial") ? "trivial" : "standard";
      const stage = size === "trivial" ? "trivial" : "needs-plan";
      st.planGate = { stage, size, at: now() }; writeState(st);
      console.log(`scoped: size=${size}, stage=${stage}${stage === "needs-plan" ? " (run /plan, then /plan-approve)" : " (trivial — edits allowed)"}`);
      break;
    }
    case "plan-approve":
      st.planGate = { ...(st.planGate || {}), stage: "plan-approved", at: now() }; writeState(st);
      console.log("plan-gate: approved — build phase unlocked."); break;
    case "plan-reset":
      st.planGate = { stage: "needs-scope", at: now() }; writeState(st); console.log("plan-gate: reset."); break;
    case "review-approve": {
      const h = stagedHash();
      if (h === "empty") { console.log("review-approve: nothing staged — `git add` your changes first."); process.exit(1); }
      writeFileSync(reviewFile(), h + "\n");
      console.log(`review-gate: approved staged diff ${h} — commit unlocked. (Editing any staged file re-locks it.)`); break;
    }
    case "review-clear":
      if (existsSync(reviewFile())) rmSync(reviewFile()); console.log("review-gate: cleared."); break;
    case "careful":
      st.careful = { on: rest[0] === "on", at: now() }; writeState(st); console.log(`careful mode: ${st.careful.on ? "ON" : "OFF"}`); break;
    case "status":
      console.log(JSON.stringify({ planGate: st.planGate || {}, careful: st.careful || {}, reviewApproved: existsSync(reviewFile()) ? readFileSync(reviewFile(), "utf8").trim() : null, stagedHash: stagedHash(), repoRoot: repoRoot() }, null, 2)); break;
    default:
      console.log("usage: gate.mjs precheck|scope [--trivial|--complex]|plan-approve|plan-reset|review-approve|review-clear|careful <on|off>|status");
      process.exit(cmd ? 2 : 0);
  }
}
main();
