#!/usr/bin/env node
// port-from-omp.mjs — mechanically port OMP (Oh-My-Pi) plugin content into
// Claude Code plugin format. Reads ../plugins/<omp-plugin> and writes the
// transformed agents/commands/skills into claude-code/plugins/<plugin>.
//
// What it transforms (the only OMP→Claude-Code deltas that are mechanical):
//   • tool names      read→Read, write→Write, edit→Edit, bash→Bash, search→Grep,
//                     find→Glob, task→Task, skill→Skill, web→WebSearch,
//                     browse→WebFetch, ask→(dropped — no Claude Code analog)
//   • model tiers     pi/smol|smol|claude-haiku-4-5→haiku, claude-sonnet-4-6→sonnet,
//                     claude-opus-4-8→opus
//   • frontmatter     thinking-level→effort; drop OMP-only keys (spawns, blocking,
//                     user-invocable); keep name/description/argument-hint/model/
//                     allowed-tools/tools
//   • body refs       `skill://dev-team-knowledge/<f>` → `dev-team-knowledge/<f>`,
//                     `read skill://<x>` → `use the /<x> skill`
//
// Everything else (hooks, statusline, MCP, manifests, installers) is hand-authored
// — those are the parts that are NOT a 1:1 mapping. Run from repo root:
//   node claude-code/scripts/port-from-omp.mjs
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync, existsSync, rmSync, copyFileSync } from "node:fs";
import { join, dirname, relative } from "node:path";

const REPO = process.cwd();
const OMP = join(REPO, "plugins");
const OUT = join(REPO, "claude-code", "plugins");

const TOOL_MAP = {
  read: "Read", write: "Write", edit: "Edit", bash: "Bash", search: "Grep",
  find: "Glob", task: "Task", skill: "Skill", todo: "TodoWrite",
  web: "WebSearch", websearch: "WebSearch", browse: "WebFetch", webfetch: "WebFetch",
  ask: null, // no Claude Code agent-frontmatter analog
};
const MODEL_MAP = {
  "pi/smol": "haiku", "smol": "haiku", "claude-haiku-4-5": "haiku",
  "claude-sonnet-4-6": "sonnet", "claude-sonnet-4-5": "sonnet",
  "claude-opus-4-8": "opus", "claude-opus-4-1": "opus",
};

// split "a, bash(git x), c" on top-level commas (ignore commas inside parens)
function splitTop(s) {
  const out = []; let depth = 0, cur = "";
  for (const ch of s) {
    if (ch === "(") depth++; if (ch === ")") depth = Math.max(0, depth - 1);
    if (ch === "," && depth === 0) { out.push(cur); cur = ""; } else cur += ch;
  }
  if (cur.trim()) out.push(cur);
  return out.map((x) => x.trim()).filter(Boolean);
}
function mapTool(tok) {
  const m = tok.match(/^([a-zA-Z_]+)(\(.*\))?$/);
  if (!m) return tok;
  const base = m[1].toLowerCase(), args = m[2] || "";
  if (!(base in TOOL_MAP)) return tok; // unknown — pass through
  const mapped = TOOL_MAP[base];
  if (mapped === null) return null; // dropped
  return mapped + args;
}
function mapTools(value) {
  // value may be a YAML inline string ("read, search") or already a list-ish
  const toks = splitTop(String(value).replace(/^\[|\]$/g, ""));
  const mapped = toks.map(mapTool).filter((x) => x !== null);
  return [...new Set(mapped)];
}
function mapModel(v) {
  const k = String(v).trim();
  return MODEL_MAP[k] || (/haiku/i.test(k) ? "haiku" : /sonnet/i.test(k) ? "sonnet" : /opus/i.test(k) ? "opus" : k);
}

function splitFrontmatter(text) {
  if (!text.startsWith("---")) return { fm: null, body: text };
  const end = text.indexOf("\n---", 3);
  if (end === -1) return { fm: null, body: text };
  const fmRaw = text.slice(3, end).replace(/^\n/, "");
  const body = text.slice(end + 4).replace(/^\n/, "");
  return { fmRaw, body };
}
// minimal line-based YAML frontmatter parse: top-level "key: value" + "key:" block scalars
function parseFm(fmRaw) {
  const lines = fmRaw.split("\n");
  const out = []; // preserve order: [key, rawValue, isBlock]
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(/^([A-Za-z0-9_-]+):(.*)$/);
    if (!m) continue;
    const key = m[1]; let val = m[2].trim();
    if (val === ">-" || val === ">" || val === "|" || val === "|-") {
      // block scalar — gather indented continuation
      const buf = [];
      while (i + 1 < lines.length && /^\s+/.test(lines[i + 1])) { buf.push(lines[++i].trim()); }
      val = buf.join(" ");
      out.push([key, val, true]);
    } else {
      out.push([key, val, false]);
    }
  }
  return out;
}
function yamlEscape(s) {
  if (/[:#>{}\[\]&*!|%@`"']/.test(s) || /^\s|\s$/.test(s)) return JSON.stringify(s);
  return s;
}
function rebuildFm(entries, kind) {
  const drop = new Set(["spawns", "blocking", "user-invocable"]);
  const lines = [];
  for (const [key, val, isBlock] of entries) {
    if (drop.has(key)) continue;
    if (key === "tools" || key === "allowed-tools") {
      const tools = mapTools(val);
      if (!tools.length) continue;
      lines.push(`${key}:`);
      for (const t of tools) lines.push(`  - ${yamlEscape(t)}`);
      continue;
    }
    if (key === "model") { lines.push(`model: ${mapModel(val)}`); continue; }
    if (key === "thinking-level") { lines.push(`effort: ${val}`); continue; }
    if (isBlock) { lines.push(`${key}: >-`); lines.push(`  ${val}`); continue; }
    lines.push(`${key}: ${val}`);
  }
  return lines.join("\n");
}
function transformBody(body) {
  return body
    .replace(/read\s+skill:\/\/([A-Za-z0-9_-]+)/g, "use the /$1 skill")
    .replace(/skill:\/\/dev-team-knowledge\//g, "dev-team-knowledge/")
    .replace(/skill:\/\/([A-Za-z0-9_-]+)/g, "the /$1 skill");
}
function transformMd(text, kind) {
  const { fmRaw, body } = splitFrontmatter(text);
  if (fmRaw == null) return text;
  const fm = rebuildFm(parseFm(fmRaw), kind);
  return `---\n${fm}\n---\n\n${transformBody(body).replace(/^\n+/, "")}`;
}

function walk(dir, cb) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name); const st = statSync(p);
    if (st.isDirectory()) walk(p, cb); else cb(p);
  }
}
function portTree(srcRel, dstRel, kind) {
  const src = join(OMP, srcRel), dst = join(OUT, dstRel);
  if (!existsSync(src)) return 0;
  let n = 0;
  walk(src, (p) => {
    const rel = relative(src, p); const outPath = join(dst, rel);
    mkdirSync(dirname(outPath), { recursive: true });
    if (p.endsWith(".md") && kind) {
      writeFileSync(outPath, transformMd(readFileSync(p, "utf8"), kind));
    } else {
      copyFileSync(p, outPath); // supporting files (json, schemas, scripts, refs)
    }
    n++;
  });
  return n;
}

// --- dev-team: agents + commands + skills ---------------------------------
let total = 0;
for (const [src, dst, kind] of [
  ["dev-team/agents", "dev-team/agents", "agent"],
  ["dev-team/commands", "dev-team/commands", "command"],
  ["dev-team/skills", "dev-team/skills", "skill"],
  // token-diet: only the model-facing skills port (extensions are replaced by hooks/statusline)
  ["token-diet/skills", "token-diet/skills", "skill"],
  // datadog: the umbrella skill
  ["datadog/skills", "datadog/skills", "skill"],
]) {
  const c = portTree(src, dst, kind);
  total += c;
  console.log(`ported ${c.toString().padStart(4)} files: ${src} → claude-code/plugins/${dst}`);
}
console.log(`\nDone. ${total} files ported.`);
