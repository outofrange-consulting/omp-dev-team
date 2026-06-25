// Framework-compliance checks for the dev-team plugin (cross-platform; used by CI).
//
// These automate what prior extraction PRs verified by hand:
//   A. Every `skill://dev-team-knowledge/<file>.md#<anchor>` reference resolves
//      — the target file exists AND the anchor matches a heading slug OR a
//      registered anchor in index.json (the project's hand-authored anchor
//      registry, which doesn't always follow strict GitHub slug rules).
//   B. Every file keyed in index.json exists.
//   C. Every finding-emitting review agent references the shared
//      review-output-discipline contract (deterministic status + grouping).
//   D. Deliberately-removed TDD identifiers don't creep back in (test-after is
//      a framework choice) — outside a small rationale/historical allowlist.
//
// Pure Node, no dependencies. Exit non-zero on any violation.
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const ROOT = "plugins/dev-team";
const KDIR = join(ROOT, "skills/dev-team-knowledge");
let failures = 0;
const fail = (check, msg) => { console.error(`FAIL [${check}] ${msg}`); failures++; };

function walk(dir, exts, out = []) {
  for (const e of readdirSync(dir)) {
    if (e === "node_modules" || e === ".git") continue;
    const p = join(dir, e), s = statSync(p);
    if (s.isDirectory()) walk(p, exts, out);
    else if (exts.some((x) => e.endsWith(x))) out.push(p);
  }
  return out;
}
function exists(p) { try { statSync(p); return true; } catch { return false; } }

// GitHub-style heading slugger (lowercase, strip punctuation except word/space/
// hyphen, each whitespace -> hyphen with no collapse, duplicate suffix -N).
function headingSlugs(file) {
  const counts = new Map(), set = new Set();
  for (const line of readFileSync(file, "utf8").split(/\r?\n/)) {
    const m = /^#{1,6}\s+(.*)$/.exec(line);
    if (!m) continue;
    const base = m[1].trim().toLowerCase().replace(/[^\w\s-]/g, "").replace(/\s/g, "-");
    let s = base;
    if (counts.has(base)) { const n = counts.get(base) + 1; counts.set(base, n); s = `${base}-${n}`; }
    else counts.set(base, 0);
    set.add(s);
  }
  return set;
}

const index = JSON.parse(readFileSync(join(KDIR, "index.json"), "utf8"));
const indexAnchorsFor = (file) => {
  const entry = index[join(KDIR, file).replaceAll("\\", "/")];
  return entry ? new Set(Object.values(entry).map((v) => v.anchor)) : new Set();
};

// ---- A. Anchor references resolve ----
const refRe = /skill:\/\/dev-team-knowledge\/([A-Za-z0-9._-]+\.md)#([A-Za-z0-9-]+)/g;
const refs = new Set();
for (const f of walk(ROOT, [".md"])) {
  const t = readFileSync(f, "utf8"); let m;
  while ((m = refRe.exec(t))) refs.add(`${m[1]}#${m[2]}`);
}
for (const r of [...refs].sort()) {
  const [file, anchor] = r.split("#");
  const fp = join(KDIR, file);
  if (!exists(fp)) { fail("anchor", `${r} — target file missing`); continue; }
  if (!headingSlugs(fp).has(anchor) && !indexAnchorsFor(file).has(anchor))
    fail("anchor", `${r} — anchor matches no heading and is not in index.json`);
}

// ---- B. index.json keyed files exist ----
for (const rel of Object.keys(index))
  if (!exists(rel)) fail("index", `${rel} — keyed in index.json but missing`);

// ---- C. Review-agent output-discipline wiring ----
const CONTRACT = '"status": "pass|warn|fail|skip"';
const ALLOW_NO_DISCIPLINE = new Set(["progress-guardian.md"]); // not a lexical finding agent
for (const a of readdirSync(join(ROOT, "agents")).filter((f) => f.endsWith(".md"))) {
  const t = readFileSync(join(ROOT, "agents", a), "utf8");
  if (t.includes(CONTRACT) && !t.includes("review-output-discipline.md") && !ALLOW_NO_DISCIPLINE.has(a))
    fail("wiring", `${a} — emits the findings contract but doesn't reference review-output-discipline.md`);
}

// ---- D. No deliberately-removed TDD identifiers ----
const FORBIDDEN = [/tdd-first/i, /tdd-guard/i, /test-driven-development/i, /RED→GREEN/, /RED-GREEN/];
const ALLOW_TDD = new Set([
  "plugins/dev-team/skills/testing-discipline/SKILL.md", // explains why ordering is dropped
  "plugins/dev-team/extensions/spec-guard.ts",           // comment: formerly tdd-guard
  "plugins/dev-team/README.md",                          // rationale: test-first not enforced
  "plugins/dev-team/README.fr.md",
]);
for (const f of walk(ROOT, [".md", ".ts"])) {
  if (ALLOW_TDD.has(f.replaceAll("\\", "/"))) continue;
  const t = readFileSync(f, "utf8");
  for (const re of FORBIDDEN) {
    const m = re.exec(t);
    if (m) { fail("test-after", `${f} — forbidden TDD identifier "${m[0]}" (test-after is the framework choice)`); break; }
  }
}

console.log(
  `Framework compliance: ${refs.size} anchor refs, ${Object.keys(index).length} index files checked — ${failures} violation(s).`
);
process.exit(failures ? 1 : 0);
