// Framework-compliance checks for this marketplace (cross-platform; used by CI).
//
// The job of this script is to make the repo unable to lie about itself. Every
// check below exists because a real, shipped defect got through review:
//
//   A. `skill://dev-team-knowledge/<file>.md#<anchor>` refs resolve.
//   B. Every file keyed in index.json exists.
//   C. Finding-emitting review agents reference the output-discipline contract.
//   D. Deliberately-removed TDD identifiers don't creep back in.
//   E. The canary sentinel stays byte-identical in the rule and the extension.
//   F. Bare `skill://<name>` refs resolve to a real SKILL (not to an agent).
//   G. Every `plugins/...` path mentioned in markdown exists.
//   H. plugin.json / package.json version parity; marketplace <-> plugin dirs;
//      every `omp.extensions` entry points at a file that exists.
//   I. No plugin command collides with an OMP builtin (native provider wins,
//      first-wins — a colliding command is permanently shadowed and silently
//      never runs).
//   J. No `${CLAUDE_PLUGIN_ROOT}` in skill/agent/prompt/rule bodies. OMP
//      substitutes it only in discovery configs, never in prose.
//   K. No references to the retired Claude Code hook era (`.../hooks/`, `.claude/`).
//   L. No settings that OMP has removed (they are deleted from config on load,
//      so writing them only litters the user's config).
//   M. Agent frontmatter matches OMP's parser: `@role` aliases, real roles, and
//      none of the Claude-Code-only keys that OMP ignores silently.
//   N. Count claims in the READMEs match the filesystem.
//
// Pure Node, no dependencies. Exit non-zero on any violation.
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, basename } from "node:path";

const ROOT = "plugins/dev-team";
const KDIR = join(ROOT, "skills/dev-team-knowledge");
const PLUGINS_DIR = "plugins";
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
const exists = (p) => existsSync(p);
const read = (p) => readFileSync(p, "utf8");
const norm = (p) => p.replaceAll("\\", "/");
const dirs = (p) => (exists(p) ? readdirSync(p).filter((e) => statSync(join(p, e)).isDirectory()) : []);
const mdFiles = (p) => (exists(p) ? readdirSync(p).filter((f) => f.endsWith(".md")) : []);

const PLUGINS = dirs(PLUGINS_DIR);

// GitHub-style heading slugger (lowercase, strip punctuation except word/space/
// hyphen, each whitespace -> hyphen with no collapse, duplicate suffix -N).
function headingSlugs(file) {
  const counts = new Map(), set = new Set();
  for (const line of read(file).split(/\r?\n/)) {
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

const index = JSON.parse(read(join(KDIR, "index.json")));
const indexAnchorsFor = (file) => {
  const entry = index[norm(join(KDIR, file))];
  return entry ? new Set(Object.values(entry).map((v) => v.anchor)) : new Set();
};

const ALL_MD = PLUGINS.flatMap((p) => walk(join(PLUGINS_DIR, p), [".md"]))
  .concat(walk("docs", [".md"]))
  .concat(["README.md", "README.fr.md"].filter(exists));

// ---- A. Anchored knowledge refs resolve ----
const refRe = /skill:\/\/dev-team-knowledge\/([A-Za-z0-9._-]+\.md)#([A-Za-z0-9-]+)/g;
const refs = new Set();
for (const f of walk(ROOT, [".md"])) {
  const t = read(f); let m;
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
for (const a of mdFiles(join(ROOT, "agents"))) {
  const t = read(join(ROOT, "agents", a));
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
  "docs/plan-gate-over-tdd.md",                          // the rationale document itself
]);
for (const f of walk(ROOT, [".md", ".ts"]).concat(walk("docs", [".md"]))) {
  if (ALLOW_TDD.has(norm(f))) continue;
  const t = read(f);
  for (const re of FORBIDDEN) {
    const m = re.exec(t);
    if (m) { fail("test-after", `${f} — forbidden TDD identifier "${m[0]}" (test-after is the framework choice)`); break; }
  }
}

// ---- E. Canary sentinel: byte-identical in the alwaysApply rule + extension ----
const CANARY_TOKEN = "DT-CANARY-7Q2F";
const canaryRule = join(ROOT, "rules/dev-team-operating-manual.md");
const canaryExt = join(ROOT, "extensions/canary.ts");
if (!exists(canaryRule)) {
  fail("canary", "rules/dev-team-operating-manual.md missing");
} else {
  const rt = read(canaryRule);
  if (!rt.includes(CANARY_TOKEN)) fail("canary", `operating-manual missing sentinel ${CANARY_TOKEN}`);
  const fm = /^---\n([\s\S]*?)\n---/.exec(rt);
  if (!fm || !/^\s*alwaysApply:\s*true\s*$/m.test(fm[1]))
    fail("canary", "operating-manual is not `alwaysApply: true` (canary rule would not load)");
}
if (!exists(canaryExt)) fail("canary", "extensions/canary.ts missing");
else if (!read(canaryExt).includes(CANARY_TOKEN))
  fail("canary", `canary.ts sentinel != ${CANARY_TOKEN} (drift between rule and extension)`);

// ---- F. Bare `skill://<name>` refs resolve to a real SKILL ----
// A skill:// URI pointing at an AGENT silently resolves to nothing. The anchored
// dev-team-knowledge form is covered by check A and skipped here.
const ALL_SKILLS = new Set(PLUGINS.flatMap((p) => dirs(join(PLUGINS_DIR, p, "skills"))));
const ALL_AGENTS = new Set(PLUGINS.flatMap((p) => mdFiles(join(PLUGINS_DIR, p, "agents")).map((f) => basename(f, ".md"))));
const bareRe = /skill:\/\/([A-Za-z0-9._-]+)(?![A-Za-z0-9._/-])/g;
for (const f of ALL_MD) {
  const t = read(f); let m;
  while ((m = bareRe.exec(t))) {
    const name = m[1];
    if (name === "dev-team-knowledge") continue; // anchored form, check A
    if (ALL_SKILLS.has(name)) continue;
    if (ALL_AGENTS.has(name)) fail("skill-uri", `${f} — skill://${name} targets an AGENT, not a skill`);
    else fail("skill-uri", `${f} — skill://${name} resolves to no skill in any plugin`);
  }
}

// ---- G. Every `plugins/...` path mentioned in markdown exists ----
const pathRe = /(?<![\w/.-])(plugins\/[A-Za-z0-9._/-]*[A-Za-z0-9._-])/g;
const IGNORE_PATH = [/\*/, /\.\.\./, /<[^>]+>/, /\$\{/];
for (const f of ALL_MD) {
  const t = read(f); let m;
  const seen = new Set();
  while ((m = pathRe.exec(t))) {
    let p = m[1].replace(/[.,;:)]+$/, "");
    if (seen.has(p) || IGNORE_PATH.some((re) => re.test(p))) continue;
    seen.add(p);
    // A trailing path segment with no extension may be a directory or prose.
    if (!exists(p)) fail("dead-path", `${f} — references ${p}, which does not exist`);
  }
}

// ---- H. Manifest integrity ----
const market = JSON.parse(read(".claude-plugin/marketplace.json"));
const marketNames = new Set(market.plugins.map((p) => p.name));
for (const p of PLUGINS) {
  if (!marketNames.has(p)) fail("manifest", `plugins/${p} exists but is not listed in marketplace.json`);
  const pj = join(PLUGINS_DIR, p, ".claude-plugin/plugin.json");
  const pkg = join(PLUGINS_DIR, p, "package.json");
  if (!exists(pj)) { fail("manifest", `plugins/${p} has no .claude-plugin/plugin.json`); continue; }
  const pjv = JSON.parse(read(pj)).version;
  if (exists(pkg)) {
    const pk = JSON.parse(read(pkg));
    if (pk.version !== pjv)
      fail("manifest", `plugins/${p}: plugin.json version ${pjv} != package.json version ${pk.version}`);
    if (!pk.license) fail("manifest", `plugins/${p}/package.json has no license field`);
    for (const ext of pk.omp?.extensions ?? []) {
      const ep = join(PLUGINS_DIR, p, ext.replace(/^\.\//, ""));
      if (!exists(ep)) fail("manifest", `plugins/${p}/package.json omp.extensions -> ${ext} does not exist`);
    }
    // An extension file that exists but is not declared never loads.
    const declared = new Set((pk.omp?.extensions ?? []).map((e) => basename(e)));
    const extDir = join(PLUGINS_DIR, p, "extensions");
    for (const e of exists(extDir) ? readdirSync(extDir).filter((x) => x.endsWith(".ts")) : [])
      if (!declared.has(e)) fail("manifest", `plugins/${p}/extensions/${e} exists but is not in omp.extensions (it will never load)`);
  }
}
for (const name of marketNames)
  if (!PLUGINS.includes(name)) fail("manifest", `marketplace.json lists ${name}, but plugins/${name} does not exist`);

// ---- I. No command collides with an OMP builtin ----
// Extracted from oh-my-pi slash-commands/builtin-registry.ts. Native providers
// (priority 100) outrank omp-plugins (90) and dedup is first-wins, so a plugin
// command with a builtin's name is permanently shadowed and silently never runs.
const OMP_BUILTIN_COMMANDS = new Set([
  "add", "add-dir", "advisor", "agents", "append", "branch", "browser", "btw", "changelog",
  "collab", "compact", "computer", "context", "copy", "debug", "dirs", "drop", "dump", "exit",
  "export", "extensions", "fast", "force", "fork", "fresh", "goal", "guided-goal", "handoff",
  "hotkeys", "install", "jobs", "join", "leave", "live", "login", "logout", "loop", "marketplace",
  "mcp", "memory", "model", "move", "new", "omfg", "pause", "pin", "plan", "plan-review",
  "plugins", "prewalk", "queue", "quit", "reload-plugins", "remove-dir", "rename", "resume",
  "retry", "session", "settings", "setup", "shake", "share", "smithery-search", "ssh", "stats",
  "switch", "tan", "todo", "tools", "tree", "usage", "vibe",
]);
for (const p of PLUGINS)
  for (const c of mdFiles(join(PLUGINS_DIR, p, "commands")))
    if (OMP_BUILTIN_COMMANDS.has(basename(c, ".md")))
      fail("collision", `plugins/${p}/commands/${c} collides with the OMP builtin /${basename(c, ".md")} — it is shadowed and never runs`);

// ---- J. No ${CLAUDE_PLUGIN_ROOT} in prose ----
// OMP substitutes it only in discovery configs (MCP command/cwd/args/env), never
// in skill/agent/prompt/rule bodies, so it reaches the model as literal text.
for (const f of ALL_MD)
  if (read(f).includes("${CLAUDE_PLUGIN_ROOT}"))
    fail("plugin-root", `${f} — uses \${CLAUDE_PLUGIN_ROOT}, which OMP does not substitute in markdown bodies`);

// ---- K. No leftovers from the Claude Code hook era ----
// This plugin's hooks were reimplemented as TypeScript extensions; there is no
// hooks/ directory and no .claude/ runtime here.
const HOOK_ERA = [/plugins\/dev-team\/hooks\//, /(?<![\w-])\.claude\/(?!plugin)/];
const ALLOW_HOOK_ERA = new Set([
  "docs/extract-from-cde-dotnetcc.md",   // historical extraction record
  "docs/upstream-v7-extraction.md",
  "docs/upstream-v7.7-7.9-extraction.md",
  "REVIEW.md",
]);
for (const f of ALL_MD) {
  if (ALLOW_HOOK_ERA.has(norm(f))) continue;
  const t = read(f);
  for (const re of HOOK_ERA)
    if (re.test(t)) { fail("hook-era", `${f} — references the retired Claude Code hook layer (${re})`); break; }
}

// ---- L. No settings OMP has removed ----
// tools.discoveryMode / tools.essentialOverride / mcp.discoveryMode were removed
// in OMP 17.0.0 and are deleted from config on load: writing them is a no-op that
// litters the user's global config.
const DEAD_SETTINGS = ["discoveryMode", "essentialOverride", "discoveryDefaultServers"];
for (const f of ALL_MD.concat(walk("scripts", [".sh", ".mjs"]), ["install.sh", "install.ps1"].filter(exists),
  PLUGINS.flatMap((p) => ["install.sh", "install.ps1", "config.snippet.yml"].map((x) => join(PLUGINS_DIR, p, x)).filter(exists)))) {
  const t = read(f);
  for (const s of DEAD_SETTINGS)
    if (t.includes(s) && !t.includes(`REMOVED in OMP 17`) && !t.includes("were REMOVED"))
      fail("dead-setting", `${f} — mentions the removed setting "${s}" without marking it removed`);
}

// ---- M. Agent frontmatter matches OMP's parser ----
// OMP parses `model` (CSV/list of patterns, first resolvable wins), `thinkingLevel`
// (kebab `thinking-level` is normalized), `tools`, `spawns`, `output`, `blocking`,
// `autoloadSkills`, `readSummarize`, `prewalk`. It has NO `effort`, and ignores
// Claude-Code-only keys silently — a silent ignore is exactly what we must catch.
const OMP_ROLES = new Set(["default", "smol", "slow", "vision", "plan", "designer", "commit", "tiny", "task", "advisor"]);
const CC_ONLY_KEYS = ["effort", "color", "memory", "permissionMode", "maxTurns", "disallowedTools", "isolation", "initialPrompt"];
for (const p of PLUGINS)
  for (const a of mdFiles(join(PLUGINS_DIR, p, "agents"))) {
    const f = join(PLUGINS_DIR, p, "agents", a);
    const fm = /^---\r?\n([\s\S]*?)\r?\n---/.exec(read(f));
    if (!fm) { fail("agent-fm", `${f} — no YAML frontmatter`); continue; }
    const body = fm[1];
    for (const k of CC_ONLY_KEYS)
      if (new RegExp(`^\\s*${k}:`, "m").test(body))
        fail("agent-fm", `${f} — declares "${k}:", which OMP's agent parser ignores silently`);
    const mm = /^\s*model:\s*(.+)$/m.exec(body);
    if (!mm) { fail("agent-fm", `${f} — no model: (it will inherit the session model)`); continue; }
    const raw = mm[1].trim().replace(/^["']|["']$/g, "");
    for (const pat of raw.split(",").map((x) => x.trim()).filter(Boolean)) {
      if (pat.startsWith("pi/"))
        fail("agent-fm", `${f} — model uses the LEGACY "pi/" role prefix (${pat}); the canonical form is "@${pat.slice(3)}"`);
      else if (pat.startsWith("@") && !OMP_ROLES.has(pat.slice(1).split(":")[0]))
        fail("agent-fm", `${f} — model references "${pat}", which is not an OMP model role`);
      if (pat.startsWith("@") && pat.includes(":"))
        fail("agent-fm", `${f} — model "${pat}" carries a :level suffix, which silently outranks thinking-level; use one surface only`);
    }
  }

// ---- N. README count claims match the filesystem ----
const counts = {
  agents: mdFiles(join(ROOT, "agents")).length,
  skills: dirs(join(ROOT, "skills")).length,
  extensions: (exists(join(ROOT, "extensions")) ? readdirSync(join(ROOT, "extensions")).filter((f) => f.endsWith(".ts")) : []).length,
  plugins: PLUGINS.length,
};
const CLAIMS = [
  [/(\d+)[ ]+specialist\/critic agents/g, "agents"],
  [/orchestrator \+ (\d+)[ ]+specialist/g, "agents"],
  [/~(\d+)[ ]+skills/g, "skills"],
  [/(?:the[ ]+)?(\d+)[ ]+extensions/g, "extensions"],
];
for (const f of ["README.md", "README.fr.md", join(ROOT, "README.md"), join(ROOT, "README.fr.md")].filter(exists)) {
  const t = read(f);
  for (const [re, key] of CLAIMS) {
    re.lastIndex = 0; let m;
    while ((m = re.exec(t))) {
      const claimed = Number(m[1]);
      if (claimed !== counts[key])
        fail("counts", `${f} — claims ${claimed} ${key}, filesystem has ${counts[key]} ("${m[0].trim()}")`);
    }
  }
}

console.log(
  `Framework compliance: ${refs.size} anchor refs, ${Object.keys(index).length} index files, ` +
  `${PLUGINS.length} plugins, ${counts.agents} agents, ${counts.skills} dev-team skills, ` +
  `${counts.extensions} extensions checked — ${failures} violation(s).`
);
process.exit(failures ? 1 : 0);
