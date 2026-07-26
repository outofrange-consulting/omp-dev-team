#!/usr/bin/env node
// Generate the dev-team registries from the filesystem:
//
//   plugins/dev-team/skills/dev-team-knowledge/agent-registry.md   (agents, prompts, knowledge)
//   plugins/dev-team/skills/dev-team-knowledge/skills-registry.md  (the invocation surface)
//
// Why generate them: the orchestrator reads these to decide what to dispatch, so
// a registry that disagrees with the filesystem routes work to something that
// isn't there — or, worse, never routes work to something that is. The
// hand-written version listed 36 of 67 skill directories, told agents skills live
// in a Claude Code path this plugin does not use, and carried per-agent "model
// tier" values that had to be re-typed every time a tier moved. Every column
// below is read off disk at run time instead.
//
// Split follows upstream (knowledge/agent-registry.md + knowledge/skills-registry.md):
// the agent catalog and the command catalog are consulted at different moments
// and have no reason to be loaded together.
//
// Honesty rules this script follows:
//   - No token estimates. There is no tokenizer here, and the old "~Tokens"
//     column was a hand-guess that drifted with every edit. Bytes are measured.
//   - The `model:` column is a mirror of frontmatter, which is the single source
//     of truth. It is safe to mirror precisely BECAUSE it is regenerated.
//   - "Used by" / "Read by" columns are computed from real references, so an
//     empty cell is a real signal (nothing cites this file) rather than an
//     omission.
//
// Usage:  node scripts/build-registries.mjs [--check]
//         --check  exits non-zero if either file on disk differs from generated
//                  output (for CI), without writing.
//
// RE-RUN THIS after adding/removing/renaming an agent, a skill directory, a
// prompt template, a knowledge file, or an extension-registered command.
//
// Pure Node, no dependencies.
import { readFileSync, writeFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, basename } from "node:path";

const ROOT = "plugins/dev-team";
const KDIR = join(ROOT, "skills/dev-team-knowledge");
const AGENT_DIR = join(ROOT, "agents");
const SKILL_DIR = join(ROOT, "skills");
const PROMPT_DIR = join(ROOT, "prompts");
const CMD_DIR = join(ROOT, "commands");
const EXT_DIR = join(ROOT, "extensions");

// The same string ci-framework-compliance.mjs check C uses to recognise a
// finding-emitting reviewer. One definition of "is a review agent", shared.
const FINDINGS_CONTRACT = '"status": "pass|warn|fail|skip"';

const read = (p) => readFileSync(p, "utf8");
const ls = (p, pred) => (existsSync(p) ? readdirSync(p).filter(pred).sort() : []);
const mdIn = (p) => ls(p, (f) => f.endsWith(".md"));
const dirsIn = (p) => ls(p, (f) => statSync(join(p, f)).isDirectory());
const bytes = (p) => statSync(p).size;
// A markdown table cell cannot contain a raw pipe or newline.
const cell = (s) => (s || "").replace(/\r?\n+/g, " ").replace(/\s+/g, " ").replace(/\|/g, "\\|").trim();

// --- frontmatter ---------------------------------------------------------
// Deliberately minimal: scalars and `- item` lists at the top level, which is
// everything the agent/skill contract actually uses. Anything richer belongs in
// the body, not in a registry column.
function frontmatter(text) {
	const m = /^---\r?\n([\s\S]*?)\r?\n---/.exec(text);
	if (!m) return {};
	const out = {};
	let key = null;
	for (const line of m[1].split(/\r?\n/)) {
		if (/^\s*#/.test(line) || !line.trim()) continue;
		const item = /^\s+-\s+(.*)$/.exec(line);
		if (item && key) {
			(out[key] = Array.isArray(out[key]) ? out[key] : []).push(item[1].trim());
			continue;
		}
		const kv = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line);
		if (!kv) continue;
		key = kv[1];
		const v = kv[2].trim();
		if (v === "" || v === ">-" || v === "|" || v === ">") out[key] = "";
		else out[key] = v.replace(/^["']|["']$/g, "");
	}
	// Folded scalars (`description: >-`) put the text on the following lines;
	// recover it so the description column is not empty for those files.
	for (const k of Object.keys(out)) {
		if (out[k] !== "") continue;
		const re = new RegExp(`^${k}:\\s*(?:>-|>|\\|)?\\s*\\n((?:[ \\t]+\\S.*\\n?)+)`, "m");
		const f = re.exec(`${m[1]}\n`);
		if (f) out[k] = f[1].split(/\r?\n/).map((l) => l.trim()).filter(Boolean).join(" ");
	}
	return out;
}

const firstSentence = (s, max = 200) => {
	const t = (s || "").trim();
	if (!t) return "";
	const stop = t.search(/\.\s|\.$/);
	const one = stop > 0 ? t.slice(0, stop + 1) : t;
	return one.length > max ? `${one.slice(0, max).replace(/\s+\S*$/, "")}…` : one;
};

// --- inventory -----------------------------------------------------------
const agents = mdIn(AGENT_DIR).map((f) => {
	const p = join(AGENT_DIR, f);
	const text = read(p);
	const fm = frontmatter(text);
	return {
		name: fm.name || basename(f, ".md"),
		file: `agents/${f}`,
		path: p,
		fm,
		text,
		isReviewer: text.includes(FINDINGS_CONTRACT),
		readOnly: !/\b(write|edit)\b/.test(fm.tools || ""),
		bytes: bytes(p),
	};
});

const skills = dirsIn(SKILL_DIR)
	.filter((d) => existsSync(join(SKILL_DIR, d, "SKILL.md")))
	.map((d) => {
		const p = join(SKILL_DIR, d, "SKILL.md");
		const fm = frontmatter(read(p));
		return {
			name: fm.name || d,
			dir: d,
			file: `skills/${d}/SKILL.md`,
			path: p,
			fm,
			bytes: bytes(p),
		};
	});

const prompts = mdIn(PROMPT_DIR).map((f) => ({
	name: basename(f, ".md"),
	file: `prompts/${f}`,
	path: join(PROMPT_DIR, f),
	bytes: bytes(join(PROMPT_DIR, f)),
}));

// The two registries this script writes are themselves knowledge files, so they
// belong in the catalog — but printing their own byte count would never reach a
// fixed point (writing the number changes the number, so `--check` could never
// pass). They are listed with the size columns blanked and the reason stated.
const SELF = new Set(["agent-registry.md", "skills-registry.md"]);
const knowledge = mdIn(KDIR)
	.filter((f) => f !== "SKILL.md")
	.map((f) => ({
		name: basename(f, ".md"),
		file: `skills/dev-team-knowledge/${f}`,
		path: join(KDIR, f),
		generated: SELF.has(f),
		bytes: SELF.has(f) ? "—" : bytes(join(KDIR, f)),
		sections: SELF.has(f) ? "—" : (read(join(KDIR, f)).match(/^#{2,6}\s+\S/gm) || []).length,
	}));

// A command file fronts exactly one skill, and says so with the `skill://<name>`
// it tells the agent to read. That reference — not the filename — is the mapping,
// which is why `/dt-plan` correctly resolves to the `plan` skill.
const commandForSkill = new Map();
for (const f of mdIn(CMD_DIR)) {
	const m = /skill:\/\/([A-Za-z0-9._-]+)/.exec(read(join(CMD_DIR, f)));
	if (m) commandForSkill.set(m[1], basename(f, ".md"));
}

// Commands registered by an extension are not skills and not command files, but
// they are part of the same invocation surface — omitting them is how a registry
// ends up advertising `/add-agent` and hiding `/plan-approve`.
const extCommands = [];
for (const f of ls(EXT_DIR, (x) => x.endsWith(".ts"))) {
	const text = read(join(EXT_DIR, f));
	const re = /registerCommand\(\s*["'`]([A-Za-z0-9:_-]+)["'`]/g;
	let m;
	while ((m = re.exec(text))) {
		const desc = /description:\s*\n?\s*["'`]([^"'`]+)/.exec(text.slice(m.index, m.index + 400));
		extCommands.push({ name: m[1], file: `extensions/${f}`, desc: desc ? desc[1] : "" });
	}
}
extCommands.sort((a, b) => a.name.localeCompare(b.name));

// --- reference graph -----------------------------------------------------
// Who cites what. Scanned over agents, skills, prompts and rules — never over the
// knowledge corpus itself, so a knowledge file cross-referencing a sibling does
// not read as a consumer.
function walkMd(dir, out = []) {
	if (!existsSync(dir)) return out;
	for (const e of readdirSync(dir)) {
		const p = join(dir, e);
		if (statSync(p).isDirectory()) walkMd(p, out);
		else if (e.endsWith(".md")) out.push(p);
	}
	return out;
}
const CITERS = [
	...walkMd(AGENT_DIR),
	...walkMd(SKILL_DIR).filter((p) => !p.replaceAll("\\", "/").includes("/dev-team-knowledge/")),
	...walkMd(PROMPT_DIR),
	...walkMd(join(ROOT, "rules")),
].map((p) => ({ p, label: labelFor(p), text: read(p) }));

function labelFor(p) {
	const n = p.replaceAll("\\", "/");
	if (n.includes("/agents/")) return basename(n, ".md");
	if (n.includes("/prompts/")) return `prompts/${basename(n, ".md")}`;
	if (n.includes("/rules/")) return `rules/${basename(n, ".md")}`;
	const m = /\/skills\/([^/]+)\//.exec(n);
	return m ? `/${m[1]}` : basename(n, ".md");
}

const citersOf = (needles) => {
	const hits = new Set();
	for (const c of CITERS) if (needles.some((n) => c.text.includes(n))) hits.add(c.label);
	return [...hits].sort();
};
const usedBy = (list, max = 6) =>
	list.length === 0 ? "—" : list.length > max ? `${list.slice(0, max).join(", ")} +${list.length - max} more` : list.join(", ");

// --- render --------------------------------------------------------------
const STAMP =
	"<!-- GENERATED by scripts/build-registries.mjs from the filesystem — do not edit by hand.\n" +
	"     Re-run it after adding, removing or renaming an agent, skill, prompt or knowledge file. -->";

function agentRegistry() {
	const team = agents.filter((a) => !a.isReviewer);
	const reviewers = agents.filter((a) => a.isReviewer);
	const L = [];
	L.push(STAMP, "", "# Agent Registry", "");
	L.push(
		"The full agent catalog. The orchestrator reads this when a routing decision needs more than the",
		"agents it already knows about. The **skills** catalog lives in `skills-registry.md` — the two are",
		"consulted at different moments, so they load separately.",
		"",
	);
	L.push(
		`Counted off disk: **${team.length} team agents**, **${reviewers.length} review agents**,`,
		`**${prompts.length} prompt templates**, **${knowledge.length} knowledge files**.`,
		"",
	);
	L.push(
		"`Model` mirrors each agent's `model:` frontmatter, which is the single source of truth OMP resolves",
		"(`@role` aliases against `modelRoles`, first *resolvable* pattern wins). It is safe to mirror here",
		"only because this table is regenerated — never hand-edit a value into it.",
		"",
	);

	L.push("## Team Agents", "");
	L.push("| Agent | File | Model | Thinking | Bytes | Focus |");
	L.push("|-------|------|-------|----------|-------|-------|");
	for (const a of team)
		L.push(
			`| ${a.name} | \`${a.file}\` | \`${cell(a.fm.model) || "—"}\` | ${cell(a.fm["thinking-level"]) || "—"} | ${a.bytes} | ${cell(firstSentence(a.fm.description))}${a.readOnly ? " *(read-only)*" : ""} |`,
		);
	L.push("");

	L.push("## Review Agents", "");
	L.push(
		"Dispatched during inline review checkpoints and full `/code-review` runs. Membership in this table is",
		"not a label — an agent is here because its body declares the shared findings contract",
		"(`\"status\": \"pass|warn|fail|skip\"`), the same signal `scripts/ci-framework-compliance.mjs` uses. An",
		"agent that stops emitting findings leaves this table automatically.",
		"",
		"`Blocking` reflects the `blocking:` frontmatter key: a blocking reviewer holds the gate, a non-blocking",
		"one is advisory. Severity→status rules are in `review-output-discipline.md`, not here.",
		"",
	);
	L.push("| Agent | File | Model | Thinking | Blocking | Bytes | What It Checks |");
	L.push("|-------|------|-------|----------|----------|-------|----------------|");
	for (const a of reviewers)
		L.push(
			`| ${a.name} | \`${a.file}\` | \`${cell(a.fm.model) || "—"}\` | ${cell(a.fm["thinking-level"]) || "—"} | ${a.fm.blocking === "true" ? "yes" : "no"} | ${a.bytes} | ${cell(firstSentence(a.fm.description))} |`,
		);
	L.push("");

	L.push("## Subagent Prompt Templates", "");
	L.push(
		"Concrete prompt templates in `prompts/` used when dispatching a subagent, so a dispatch is reproducible.",
		"`Referenced by` is computed from real references — an empty cell means nothing dispatches through it.",
		"",
	);
	L.push("| Template | File | Bytes | Referenced by |");
	L.push("|----------|------|-------|---------------|");
	for (const p of prompts)
		L.push(`| ${p.name} | \`${p.file}\` | ${p.bytes} | ${usedBy(citersOf([`prompts/${p.name}.md`]).filter((x) => x !== `prompts/${p.name}`))} |`);
	L.push("");

	L.push("## Knowledge Files", "");
	L.push(
		"Progressive disclosure: agents read these on demand instead of carrying detection patterns inline.",
		"They live in `skills/dev-team-knowledge/` — reachable from any working directory as",
		"`skill://dev-team-knowledge/<file>`, and resolvable section-by-section through `index.json`. (There is",
		"no `knowledge/` directory in this plugin; that path is upstream's layout.)",
		"",
		"`Read by` is computed from actual `skill://` and filename references in agents, skills, prompts and",
		"rules — cross-references between knowledge files are excluded, so an empty cell means no consumer.",
		"The two generated registries show no size: printing their own byte count could never settle, because",
		"writing the number changes it.",
		"",
	);
	L.push("| Name | File | Bytes | Sections | Read by |");
	L.push("|------|------|-------|----------|---------|");
	for (const k of knowledge)
		L.push(
			`| ${k.name} | \`${k.file}\` | ${k.bytes} | ${k.sections} | ${usedBy(citersOf([`dev-team-knowledge/${k.name}.md`, `\`${k.name}.md\``]))} |`,
		);
	L.push("");

	const subdirs = ls(KDIR, (f) => statSync(join(KDIR, f)).isDirectory());
	if (subdirs.length) {
		L.push("### Knowledge directories", "");
		L.push("| Directory | Files | Read by |");
		L.push("|-----------|-------|---------|");
		for (const d of subdirs)
			L.push(
				`| \`skills/dev-team-knowledge/${d}/\` | ${readdirSync(join(KDIR, d)).length} | ${usedBy(citersOf([`dev-team-knowledge/${d}/`, `${d}/`]))} |`,
			);
		L.push("");
	}
	return `${L.join("\n")}\n`;
}

function skillsRegistry() {
	const L = [];
	L.push(STAMP, "", "# Skills Registry", "");
	L.push(
		"Every skill this plugin ships and how to invoke it. The agent catalog lives in `agent-registry.md`.",
		"",
		`Counted off disk: **${skills.length} skills**, of which **${skills.filter((s) => commandForSkill.has(s.name)).length}** are fronted by a`,
		`command file and **${extCommands.length}** further commands are registered by extensions.`,
		"",
	);
	L.push(
		"**Invocation.** OMP names a skill's command `skill:<name>` — so a skill with no command file is invoked",
		"as `/skill:<name>`, never as a bare `/<name>` and never with a plugin namespace. A skill fronted by a",
		"file in `commands/` is invoked by that command's own name, which is why `/dt-plan` runs the `plan` skill",
		"(a plugin command named `plan` would be permanently shadowed by the OMP builtin). A skill marked",
		"`user-invocable: false` is a worker: it is read by another skill or agent, not called by a human.",
		"",
	);
	L.push("## Command Table", "");
	L.push("| Invoke | Skill | File | Role | Bytes | What It Does |");
	L.push("|--------|-------|------|------|-------|--------------|");
	for (const s of skills) {
		const cmd = commandForSkill.get(s.name);
		const invocable = String(s.fm["user-invocable"]).toLowerCase() !== "false";
		const invoke = cmd ? `\`/${cmd}\`` : invocable ? `\`/skill:${s.name}\`` : "— *(worker)*";
		L.push(
			`| ${invoke} | ${s.name} | \`${s.file}\` | ${cell(s.fm.role) || "—"} | ${s.bytes} | ${cell(firstSentence(s.fm.description))} |`,
		);
	}
	L.push("");

	L.push("## Commands registered by extensions", "");
	L.push(
		"Not skills — these are registered in TypeScript at load time. They are listed here because the",
		"invocation surface a user sees is the union of both, and a registry that shows only skills is how a",
		"nonexistent command ends up advertised while a real one stays hidden.",
		"",
	);
	L.push("| Command | Registered in |");
	L.push("|---------|---------------|");
	for (const c of extCommands) L.push(`| \`/${c.name}\` | \`${c.file}\` |`);
	L.push("");

	L.push("## Skills used by agents", "");
	L.push(
		"Computed from each agent's `autoload-skills:` frontmatter (OMP injects those skills into the agent's",
		"context on dispatch) plus any `skill://<name>` reference in its body. An agent with a `## Skills` section",
		"and no `autoload-skills:` is naming skills it will not actually receive.",
		"",
	);
	L.push("| Agent | Autoloaded skills | Referenced in body |");
	L.push("|-------|-------------------|--------------------|");
	const skillNames = new Set(skills.map((s) => s.name));
	for (const a of agents) {
		const auto = Array.isArray(a.fm["autoload-skills"]) ? a.fm["autoload-skills"] : [];
		const body = [
			...new Set(
				[...a.text.matchAll(/skill:\/\/([A-Za-z0-9._-]+)(?![A-Za-z0-9._/-])/g)]
					.map((m) => m[1])
					.filter((n) => skillNames.has(n) && !auto.includes(n)),
			),
		].sort();
		if (!auto.length && !body.length) continue;
		L.push(`| ${a.name} | ${auto.length ? auto.join(", ") : "—"} | ${body.length ? body.join(", ") : "—"} |`);
	}
	L.push("");
	return `${L.join("\n")}\n`;
}

// --- emit ----------------------------------------------------------------
const targets = [
	[join(KDIR, "agent-registry.md"), agentRegistry()],
	[join(KDIR, "skills-registry.md"), skillsRegistry()],
];

if (process.argv.includes("--check")) {
	let stale = 0;
	for (const [p, out] of targets) {
		const cur = existsSync(p) ? read(p) : "";
		if (cur !== out) {
			console.error(`FAIL ${p.replaceAll("\\", "/")} is out of date — run \`node scripts/build-registries.mjs\``);
			stale++;
		}
	}
	if (stale) process.exit(1);
	console.log("registries up to date.");
	process.exit(0);
}

for (const [p, out] of targets) writeFileSync(p, out);
console.log(
	`Wrote agent-registry.md (${agents.filter((a) => !a.isReviewer).length} team + ${agents.filter((a) => a.isReviewer).length} review agents, ` +
		`${prompts.length} prompts, ${knowledge.length} knowledge files) and ` +
		`skills-registry.md (${skills.length} skills, ${extCommands.length} extension commands).`,
);
