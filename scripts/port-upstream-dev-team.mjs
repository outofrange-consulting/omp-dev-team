// port-upstream-dev-team.mjs — re-port bdfinst/agentic-dev-team's `dev-team`
// plugin into this marketplace, applying ONLY the Claude Code -> Oh-My-Pi format
// conversion. The substance (agent prompts, skill bodies, knowledge corpus, and
// every Python hook and script) is copied byte-for-byte.
//
// WHY A SCRIPT AND NOT A HAND PORT: the previous port drifted so far from
// upstream that reconciling it took a full multi-agent review. A deterministic,
// re-runnable converter means the next upstream bump is `git pull` in the clone
// plus one command, and every deviation from upstream is visible as either a
// rule in this file or a file listed in LOCAL_ONLY.
//
// Usage:
//   node scripts/port-upstream-dev-team.mjs --from <path-to-adt-clone> [--check]
//
//   --check  convert into a temp dir and diff against the tree on disk; exit
//            non-zero if they differ. This is what CI runs, so a hand edit to a
//            ported file fails the build instead of silently becoming drift.
//
// ---------------------------------------------------------------------------
// THE CONVERSION RULES (each one exists because OMP's contract differs)
// ---------------------------------------------------------------------------
//
// 1. AGENT FRONTMATTER. OMP's parser is packages/coding-agent/src/discovery/
//    helpers.ts (`parseAgentFields`). It reads `model` as a CSV of patterns and
//    takes the FIRST RESOLVABLE one; it has no `effort` key (the reasoning dial
//    is `thinking-level`); and it silently IGNORES Claude-Code-only keys, which
//    is the dangerous case — a `memory: project` that does nothing looks like it
//    works. Upstream's alias -> our role list:
//        haiku  -> "@smol, @default"
//        sonnet -> "@plan, @default"
//        opus   -> "@slow, @plan, @default"
//    Every list ends in @default so an agent still routes when the user has not
//    pasted the config snippet. `effort: high` -> `thinking-level: high`.
//
// 2. TOOL NAMES. Claude Code capitalizes (Read/Bash/Agent); OMP lowercases and
//    renames a few (Agent->task, AskUserQuestion->ask). OMP's `tools:` is a flat
//    CSV with no per-command scoping, so `Bash(git *)` collapses to `bash`.
//
// 3. SKILL PRELOADS. Upstream `skills:` -> OMP `autoload-skills:`.
//
// 4. ${CLAUDE_PLUGIN_ROOT}. OMP substitutes this ONLY in discovery configs (MCP
//    command/cwd/args/env) — never inside a markdown body, where it reaches the
//    model as literal text. Two destinations:
//      - .../knowledge/X.md  -> skill://dev-team-knowledge/X.md  (135 sites)
//      - everything else     -> $DEV_TEAM_ROOT/...               (82 sites)
//    $DEV_TEAM_ROOT is exported at startup by extensions/plugin-root.ts.
//
// 5. KNOWLEDGE LOCATION. Upstream keeps knowledge/ at the plugin root. OMP has
//    no discovery for that, so it becomes skills/dev-team-knowledge/, reachable
//    via skill://. Content is untouched.
//
// 6. HOOKS. OMP has no `type: "command"` hooks — `--hook` is an alias for
//    `--extension` and expects a JS/TS factory. The 31 Python hooks are copied
//    verbatim and driven by ONE generic shim (extensions/hook-bridge.ts) that
//    translates OMP events into upstream's stdin-JSON contract and its exit-code
//    convention (0 pass / 1 advisory / 2 block). hooks.json is rewritten into
//    hooks/omp-hooks.json, the manifest the shim reads.
//
// Anything this script cannot express mechanically is listed in NEEDS_REVIEW and
// printed at the end, so residue is reported rather than silently dropped.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, rmSync, cpSync, existsSync } from "node:fs";
import { join, dirname, relative, basename } from "node:path";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { execFileSync } from "node:child_process";

const args = process.argv.slice(2);
const FROM = (() => {
  const i = args.indexOf("--from");
  if (i >= 0 && args[i + 1]) return args[i + 1];
  const env = process.env.ADT_CLONE;
  if (env) return env;
  console.error("usage: node scripts/port-upstream-dev-team.mjs --from <adt-clone>/plugins/dev-team");
  process.exit(2);
})();
const CHECK = args.includes("--check");
const DEST_REAL = "plugins/dev-team";
const DEST = CHECK ? mkdtempSync(join(tmpdir(), "devteam-port-")) : DEST_REAL;

const NEEDS_REVIEW = [];
const note = (file, msg) => NEEDS_REVIEW.push(`${file}: ${msg}`);

// --- Files we own outright: never overwritten by, nor removed for, the port ---
// Each entry is a deliberate local addition with a reason. Keep this list short;
// it is the total surface of our divergence from upstream.
const LOCAL_ONLY = [
  "README.fr.md",                     // this marketplace ships EN+FR
  "config.snippet.yml",               // OMP config; upstream has no equivalent
  "install.sh",                       // OMP-flavoured installer
  "install.ps1",                      // Windows installer; upstream is POSIX-only
  "package.json",                     // OMP extension manifest
  ".claude-plugin/plugin.json",       // marketplace manifest
  ".mcp.json",                        // OMP MCP config
  "extensions",                       // the hook bridge + plugin-root exporter
];

// --- 1. model / effort -----------------------------------------------------
const MODEL_MAP = {
  haiku: '"@smol, @default"',
  sonnet: '"@plan, @default"',
  opus: '"@slow, @plan, @default"',
  fable: '"@slow, @plan, @default"',
  inherit: '"@default"',
};

// --- 2. tool names ---------------------------------------------------------
const TOOL_MAP = {
  Read: "read", Write: "write", Edit: "edit", Grep: "grep", Glob: "glob",
  Bash: "bash", Agent: "task", Skill: null, AskUserQuestion: "ask",
  NotebookEdit: "edit", WebFetch: "web_search", WebSearch: "web_search",
  TodoWrite: "todo", Task: "task",
};
// MCP servers upstream depends on that this marketplace does not ship. Dropping
// the grant is correct — a tools: entry for an absent server grants nothing —
// but it is reported so the capability loss is visible, not silent.
const DROPPED_MCP = /^mcp__(codegraph|plugin_repowise_repowise)/;

// Split on commas at depth 0 only: `Bash(npm run *, npx *)` is ONE grant, and a
// naive split turns its inner commas into bogus tool names.
function splitTopLevel(value) {
  const out = [];
  let depth = 0, cur = "";
  for (const ch of value) {
    if (ch === "(") depth++;
    else if (ch === ")") depth = Math.max(0, depth - 1);
    if (ch === "," && depth === 0) { out.push(cur); cur = ""; continue; }
    cur += ch;
  }
  out.push(cur);
  return out.map((s) => s.trim()).filter(Boolean);
}

function mapTools(value, file) {
  const out = [];
  const dropped = new Set();
  for (let raw of splitTopLevel(value)) {
    const bare = raw.replace(/\(.*$/, "").trim();       // Bash(git *) -> Bash
    if (DROPPED_MCP.test(bare)) { dropped.add(bare.split("__")[1]); continue; }
    if (bare.startsWith("mcp__")) { out.push(bare); continue; }
    if (bare === "Skill") continue;   // no OMP tool; skills are /skill:<name>
    if (!(bare in TOOL_MAP)) { note(file, `unknown tool "${bare}" left as-is`); out.push(bare); continue; }
    const mapped = TOOL_MAP[bare];
    if (mapped === null) continue;                       // Skill has no OMP tool
    if (!out.includes(mapped)) out.push(mapped);
  }
  if (dropped.size) note(file, `dropped MCP grants for servers this marketplace does not ship: ${[...dropped].join(", ")}`);
  return out.join(", ");
}

// --- 4. ${CLAUDE_PLUGIN_ROOT} ----------------------------------------------
function convertPluginRoot(text) {
  return text
    .replace(/\$\{CLAUDE_PLUGIN_ROOT\}\/knowledge\/([A-Za-z0-9._/-]+\.md)/g, "skill://dev-team-knowledge/$1")
    .replace(/\$\{CLAUDE_PLUGIN_ROOT\}\/knowledge\//g, "skill://dev-team-knowledge/")
    .replace(/\$\{CLAUDE_PLUGIN_ROOT\}/g, "$DEV_TEAM_ROOT");
}

// --- prose fixes that would otherwise actively mislead the model ------------
// Deliberately narrow: an agent told to "call AskUserQuestion" would call a tool
// that does not exist here. Casual prose like "the Read tool" is left alone —
// the model maps it, and rewriting prose is where a "format-only" port starts
// silently becoming a rewrite.
function convertProse(text) {
  return text
    .replace(/\bAskUserQuestion\b/g, "the `ask` tool")
    .replace(/\bSkill\((\w[\w-]*)[^)]*\)/g, "/skill:$1")
    .replace(/\bthe `?Agent`? tool\b/g, "the `task` tool");
}

// --- frontmatter ------------------------------------------------------------
function splitFrontmatter(text) {
  const m = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/.exec(text);
  if (!m) return null;
  return { fm: m[1], body: text.slice(m[0].length), raw: m[0] };
}

const AGENT_DROP = ["color", "memory", "permissionMode", "maxTurns", "isolation", "background", "disallowedTools", "initialPrompt"];

function convertAgent(text, file) {
  const parts = splitFrontmatter(text);
  if (!parts) { note(file, "no frontmatter — copied verbatim"); return text; }
  const lines = parts.fm.split(/\r?\n/);
  const out = [];
  let i = 0;
  let effort = null;
  const dropped = [];
  while (i < lines.length) {
    const line = lines[i];
    const key = /^([A-Za-z][\w-]*):(.*)$/.exec(line);
    if (!key) { out.push(line); i++; continue; }
    const [, k, restRaw] = key;
    const rest = restRaw.trim();
    // gather a block scalar / list belonging to this key
    const block = [];
    let j = i + 1;
    while (j < lines.length && /^\s+\S/.test(lines[j])) { block.push(lines[j]); j++; }

    if (AGENT_DROP.includes(k)) { dropped.push(k); i = j; continue; }
    if (k === "effort") { effort = rest; i = j; continue; }
    if (k === "model") {
      const mapped = MODEL_MAP[rest];
      if (!mapped) { note(file, `unmapped model "${rest}" — left as-is`); out.push(line); }
      else out.push(`model: ${mapped}`);
      i = j; continue;
    }
    if (k === "tools") { out.push(`tools: ${mapTools(rest, file)}`); i = j; continue; }
    if (k === "skills") {
      out.push("autoload-skills:");
      for (const b of block) out.push(b);
      i = j; continue;
    }
    out.push(line);
    for (const b of block) out.push(b);
    i = j;
  }
  if (effort) {
    const mi = out.findIndex((l) => l.startsWith("model:"));
    out.splice(mi >= 0 ? mi + 1 : out.length, 0, `thinking-level: ${effort}`);
  }
  if (dropped.length) {
    out.push(`# Dropped by the port (OMP's agent parser ignores these silently): ${dropped.join(", ")}`);
  }
  return `---\n${out.join("\n")}\n---\n${parts.body}`;
}

function convertSkill(text, file) {
  const parts = splitFrontmatter(text);
  if (!parts) return text;
  const lines = parts.fm.split(/\r?\n/).map((line) => {
    const m = /^allowed-tools:(.*)$/.exec(line);
    if (!m || !m[1].trim() || m[1].trim() === ">-") return line;
    return `allowed-tools: ${mapTools(m[1], file)}`;
  });
  return `---\n${lines.join("\n")}\n---\n${parts.body}`;
}

// --- copy -------------------------------------------------------------------
const TEXT_EXT = [".md", ".json", ".yaml", ".yml", ".txt", ".py", ".sh", ".toml"];
const isText = (p) => TEXT_EXT.some((e) => p.endsWith(e));

function walk(dir, out = []) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    if (statSync(p).isDirectory()) walk(p, out);
    else out.push(p);
  }
  return out;
}

// Where each upstream top-level dir lands here.
function destFor(rel) {
  if (rel.startsWith("knowledge/")) return join("skills/dev-team-knowledge", rel.slice("knowledge/".length));
  return rel;
}

function main() {
  if (!existsSync(join(FROM, "agents"))) {
    console.error(`not an agentic-dev-team plugin dir: ${FROM}`);
    process.exit(2);
  }

  // Preserve our own files across the wipe.
  const keep = new Map();
  if (!CHECK) {
    for (const rel of LOCAL_ONLY) {
      const p = join(DEST_REAL, rel);
      if (!existsSync(p)) continue;
      const stash = mkdtempSync(join(tmpdir(), "keep-"));
      cpSync(p, join(stash, basename(rel)), { recursive: true });
      keep.set(rel, join(stash, basename(rel)));
    }
    rmSync(DEST_REAL, { recursive: true, force: true });
  }
  mkdirSync(DEST, { recursive: true });

  let converted = 0, verbatim = 0;
  for (const abs of walk(FROM)) {
    const rel = relative(FROM, abs).replaceAll("\\", "/");
    const dest = join(DEST, destFor(rel));
    mkdirSync(dirname(dest), { recursive: true });

    if (!isText(abs)) { cpSync(abs, dest); verbatim++; continue; }

    let text = readFileSync(abs, "utf8");
    const before = text;
    text = convertPluginRoot(text);
    // Prose rewrites apply to the BODY only. Running them over frontmatter
    // rewrote `allowed-tools: AskUserQuestion` into prose before the tool mapper
    // ever saw it, producing an "unknown tool" entry in the manifest.
    if (rel.endsWith(".md")) {
      const parts = splitFrontmatter(text);
      text = parts ? parts.raw + convertProse(parts.body) : convertProse(text);
    }
    if (rel.startsWith("agents/") && rel.endsWith(".md")) text = convertAgent(text, rel);
    if (rel.endsWith("/SKILL.md")) text = convertSkill(text, rel);
    writeFileSync(dest, text);
    text === before ? verbatim++ : converted++;
  }

  // Upstream's CLAUDE.md is the always-loaded operating manual. OMP does not
  // auto-load a plugin-root CLAUDE.md; its equivalent is a rule with
  // `alwaysApply: true`. Emit one that carries the body verbatim, and keep the
  // original file too so the port stays diffable against upstream.
  const claudeMd = join(DEST, "CLAUDE.md");
  if (existsSync(claudeMd)) {
    const body = readFileSync(claudeMd, "utf8");
    mkdirSync(join(DEST, "rules"), { recursive: true });
    writeFileSync(join(DEST, "rules/dev-team-operating-manual.md"),
      `---\nalwaysApply: true\ndescription: dev-team operating manual (upstream CLAUDE.md, always loaded)\n---\n\n` +
      `<!-- GENERATED from CLAUDE.md by scripts/port-upstream-dev-team.mjs.\n` +
      `     Upstream ships this as the harness's always-loaded context file; OMP's\n` +
      `     equivalent is an alwaysApply rule. Edit CLAUDE.md, not this file. -->\n\n` +
      body);
  }

  // hooks.json is Claude Code's registration format. Translate it into the flat
  // manifest extensions/hook-bridge.ts reads: event -> [{matcher, scripts}].
  const hooksJson = join(DEST, "hooks/hooks.json");
  if (existsSync(hooksJson)) {
    const src = JSON.parse(readFileSync(hooksJson, "utf8"));
    const out = {};
    for (const [ev, groups] of Object.entries(src.hooks ?? {})) {
      const g2 = [];
      for (const g of groups) {
        const scripts = [];
        for (const h of g.hooks ?? []) {
          for (const tok of String(h.command ?? "").replaceAll('"', " ").split(/\s+/)) {
            if (tok.endsWith(".py")) scripts.push(tok.split("/").pop());
          }
        }
        if (scripts.length) g2.push(g.matcher ? { matcher: g.matcher, scripts } : { scripts });
      }
      if (g2.length) out[ev] = g2;
    }
    writeFileSync(join(DEST, "hooks/omp-hooks.json"), `${JSON.stringify(out, null, 2)}\n`);
  }

  // knowledge/ needs a SKILL.md or OMP will not discover it.
  const kdir = join(DEST, "skills/dev-team-knowledge");
  if (existsSync(kdir) && !existsSync(join(kdir, "SKILL.md"))) {
    writeFileSync(join(kdir, "SKILL.md"), KNOWLEDGE_SKILL);
  }

  if (!CHECK) {
    for (const [rel, stash] of keep) {
      const p = join(DEST_REAL, rel);
      mkdirSync(dirname(p), { recursive: true });
      cpSync(stash, p, { recursive: true });
    }
  }

  console.log(`ported ${converted + verbatim} files from ${FROM}`);
  console.log(`  ${converted} converted, ${verbatim} byte-identical`);
  if (NEEDS_REVIEW.length) {
    console.log(`\n${NEEDS_REVIEW.length} item(s) the converter could not express mechanically:`);
    for (const n of NEEDS_REVIEW) console.log(`  - ${n}`);
  }

  if (CHECK) {
    const diff = execFileSync("git", ["diff", "--no-index", "--stat", DEST_REAL, DEST], { encoding: "utf8" }).trim();
    rmSync(DEST, { recursive: true, force: true });
    if (diff) {
      console.error("\nFAIL plugins/dev-team differs from a fresh conversion of upstream:");
      console.error(diff);
      console.error("\nEdit the converter or add the file to LOCAL_ONLY — do not hand-edit a ported file.");
      process.exit(1);
    }
    console.log("plugins/dev-team matches a fresh conversion of upstream.");
  }
}

const KNOWLEDGE_SKILL = `---
name: dev-team-knowledge
description: >-
  Reference corpus for the dev-team plugin — test strategy, CD maturity, domain
  modelling, review rubrics, OWASP detection, security contracts, and the agent
  and skills registries. Read on demand via skill://dev-team-knowledge/<file>.md;
  never loaded wholesale.
---

# dev-team knowledge

This directory is upstream agentic-dev-team's \`knowledge/\` corpus, copied
byte-for-byte. It lives under \`skills/\` because that is the only location OMP
discovers, and it carries this SKILL.md for the same reason — the content itself
is unmodified.

Reference a file as \`skill://dev-team-knowledge/<file>.md\`, optionally with a
heading anchor. \`index.json\` maps every file to its sections and is generated by
\`scripts/build-knowledge-index.mjs\`.
`;

main();
