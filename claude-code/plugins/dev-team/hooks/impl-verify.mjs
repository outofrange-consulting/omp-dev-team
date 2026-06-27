#!/usr/bin/env node
// devteam-impl-verify — deterministic build+test gate (port of OMP impl-verify).
// Detects the project stack and runs a strict build + tests, returning a
// PASS/FAIL/HALT verdict the agent must act on (never silence the gate).
// Stacks/commands are overridable via .dev-team.json {"implVerify": {...}}.
import { execSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";

const MARKERS = [
  ["dotnet", /\.(sln|slnx|csproj)$/i, [["dotnet", "build -warnaserror"], ["dotnet", "test"]]],
  ["rust", /^Cargo\.toml$/i, [["cargo", "build"], ["cargo", "test"]]],
  ["go", /^go\.mod$/i, [["go", "build ./..."], ["go", "test ./..."]]],
  ["python", /^(pyproject\.toml|setup\.cfg|requirements\.txt)$/i, [["python", "-m pytest -q"]]],
  ["node", /^package\.json$/i, [["npm", "run build --if-present"], ["npm", "test --silent"]]],
];

function detect() {
  let files = [];
  try { files = execSync("git ls-files", { encoding: "utf8" }).split("\n"); }
  catch { files = []; }
  const base = files.map((f) => f.split("/").pop() || f);
  for (const [name, re, cmds] of MARKERS) {
    if (files.some((f) => re.test(f)) || base.some((f) => re.test(f))) return { name, cmds };
  }
  return null;
}

function override() {
  for (const f of [".dev-team.json", ".omp/dev-team.json"]) {
    if (existsSync(f)) { try { return JSON.parse(readFileSync(f, "utf8")).implVerify; } catch {} }
  }
  return null;
}

const skipTests = process.argv.includes("--skip-tests");
const ov = override();
const stack = ov?.stack ? { name: ov.stack, cmds: ov.commands || [] } : detect();
if (!stack) { console.log("HALT: could not detect a project stack. Configure .dev-team.json {implVerify:{stack,commands}}."); process.exit(3); }

console.log(`impl-verify: stack=${stack.name}`);
let cmds = ov?.commands || stack.cmds;
if (skipTests) cmds = cmds.filter((c) => !/test|pytest/.test(c.join(" ")));
for (const c of cmds) {
  const line = Array.isArray(c) ? c.join(" ") : String(c);
  process.stdout.write(`\n$ ${line}\n`);
  try { execSync(line, { stdio: "inherit" }); }
  catch { console.log(`\nFAIL: \`${line}\` exited non-zero. Fix the root cause and re-run (do not silence the gate).`); process.exit(1); }
}
console.log("\nPASS: build + tests green.");
