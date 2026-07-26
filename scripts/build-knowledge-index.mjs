#!/usr/bin/env node
// Generate plugins/dev-team/skills/dev-team-knowledge/index.json from the
// markdown files on disk.
//
// Why generate it: the index is the entry point agents use to resolve a section
// anchor before reading a whole knowledge file, and it was hand-maintained. A
// hand-maintained index of 39 files and ~240 sections drifts silently — the
// keyed FILE is checked by CI (ci-framework-compliance.mjs check B) but the
// section NAME never was, so renaming a heading left an index entry pointing at
// a section that no longer exists and an agent following it read nothing. Two
// such entries had already rotted. Generating removes that whole class of drift:
// the index cannot describe a heading the file doesn't have.
//
// Output shape — deliberately the SAME shape the previous hand-written file had,
// because ci-framework-compliance.mjs reads it:
//
//   {
//     "<repo-relative path>": {
//       "__title": "<H1 text>",           // document title
//       "__bytes": 1234,                   // file size on disk
//       "<Section name>": { "summary": "<first content line>", "anchor": "<slug>" },
//       ...
//     }
//   }
//
// The two `__`-prefixed keys carry the per-document metadata (title, size). They
// are NOT section entries; the prefix is what keeps them distinguishable, and the
// generator hard-fails if a real heading ever slugs into that namespace. Keeping
// them as siblings rather than nesting the sections under a `sections` key is
// intentional: `ci-framework-compliance.mjs` does
// `Object.values(entry).map(v => v.anchor)`, and nesting would silently empty
// that set.
//
// Anchors are GitHub-style heading slugs produced by the SAME algorithm
// ci-framework-compliance.mjs uses (`headingSlugs`), including its duplicate
// counter over every heading level. If the two ever diverge, every anchored
// `skill://dev-team-knowledge/<file>.md#<anchor>` ref becomes unverifiable — so
// the algorithm below is a deliberate mirror, not an independent implementation.
//
// Usage:  node scripts/build-knowledge-index.mjs [--check]
//         --check  exits non-zero if the file on disk differs from generated
//                  output (for CI), without writing.
//
// Pure Node, no dependencies.
import { readFileSync, writeFileSync, readdirSync, statSync } from "node:fs";
import { join } from "node:path";

const KDIR = "plugins/dev-team/skills/dev-team-knowledge";
// SKILL.md is the corpus's own entry point, not a corpus document. Indexing it
// would make the map self-referential and add a key nothing resolves against.
const EXCLUDE = new Set(["SKILL.md"]);
const MAX_SUMMARY = 240;

const posix = (p) => p.replaceAll("\\", "/");

// --- heading slugs -------------------------------------------------------
// Mirror of ci-framework-compliance.mjs `headingSlugs`: lowercase, drop every
// character that is not word/whitespace/hyphen, map each whitespace char to a
// hyphen with no collapsing, and suffix `-N` on the Nth duplicate. The counter
// spans ALL heading levels (H1 included) exactly as the checker does, so an H1
// and an H2 with the same text produce the same pair of slugs on both sides.
function slugger() {
	const counts = new Map();
	return (text) => {
		const base = text
			.trim()
			.toLowerCase()
			.replace(/[^\w\s-]/g, "")
			.replace(/\s/g, "-");
		if (counts.has(base)) {
			const n = counts.get(base) + 1;
			counts.set(base, n);
			return `${base}-${n}`;
		}
		counts.set(base, 0);
		return base;
	};
}

// --- summary extraction --------------------------------------------------
// The first unit of real content under a heading. Fenced code blocks, HTML
// comments and blank lines are skipped: a summary that reads "```json" tells a
// caller nothing about whether this is the section it wants.
//
// The unit depends on what the section opens with, because these files are hard
// wrapped — taking literally the first LINE would cut most summaries mid-clause:
//   - a table  -> the header row alone (the rest is data, not a description)
//   - a list   -> the first item, including its wrapped continuation lines
//   - prose    -> the whole first paragraph, unwrapped to one line
function firstContentLine(lines) {
	const clean = [];
	let inFence = false;
	let fenceMark = "";
	for (const raw of lines) {
		const line = raw.trim();
		if (inFence) {
			if (line.startsWith(fenceMark)) inFence = false;
			continue;
		}
		if (/^(```|~~~)/.test(line)) {
			inFence = true;
			fenceMark = line.slice(0, 3);
			// A fence ends whatever block preceded it.
			if (clean.length) break;
			continue;
		}
		if (line.startsWith("<!--")) continue;
		if (!line) {
			if (clean.length) break; // blank line closes the first block
			continue;
		}
		clean.push(line);
	}
	if (!clean.length) return "";

	const isTable = clean[0].startsWith("|");
	const isItem = /^([-*+]\s+|\d+\.\s+)/.test(clean[0]);

	let take;
	if (isTable) {
		take = [clean[0]];
	} else if (isItem) {
		// Keep wrapped continuation lines, stop at the next item.
		take = [clean[0]];
		for (const l of clean.slice(1)) {
			if (/^([-*+]\s+|\d+\.\s+)/.test(l)) break;
			take.push(l);
		}
	} else {
		take = clean;
	}

	const text = take
		.join(" ")
		.replace(/^>\s?/, "")
		.replace(/^[-*+]\s+/, "")
		.replace(/^\d+\.\s+/, "")
		.replace(/\s+/g, " ")
		.trim();
	if (!text) return "";
	return text.length > MAX_SUMMARY
		? `${text.slice(0, MAX_SUMMARY).replace(/\s+\S*$/, "")}…`
		: text;
}

// --- build ---------------------------------------------------------------
function buildIndex() {
	const files = readdirSync(KDIR)
		.filter((f) => f.endsWith(".md") && !EXCLUDE.has(f))
		.filter((f) => statSync(join(KDIR, f)).isFile())
		.sort();

	const index = {};
	const problems = [];

	for (const file of files) {
		const path = posix(join(KDIR, file));
		const text = readFileSync(join(KDIR, file), "utf8");
		const lines = text.split(/\r?\n/);
		const slug = slugger();

		let title = "";
		const sections = [];
		let current = null;
		let inFence = false;
		let fenceMark = "";

		for (const raw of lines) {
			const t = raw.trim();
			// A `#` inside a fenced block is code, not a heading.
			if (inFence) {
				if (t.startsWith(fenceMark)) inFence = false;
				if (current) current.body.push(raw);
				continue;
			}
			if (/^(```|~~~)/.test(t)) {
				inFence = true;
				fenceMark = t.slice(0, 3);
				if (current) current.body.push(raw);
				continue;
			}
			const m = /^(#{1,6})\s+(.*)$/.exec(raw);
			if (!m) {
				if (current) current.body.push(raw);
				continue;
			}
			const level = m[1].length;
			const name = m[2].trim().replace(/\s+#+\s*$/, "");
			const anchor = slug(name);
			if (level === 1 && !title) {
				// The H1 is the document title, not a section — but it still
				// consumes a slug so the duplicate counter stays in step.
				title = name;
				current = null;
				continue;
			}
			if (anchor.startsWith("__"))
				problems.push(`${path}: heading "${name}" slugs into the reserved __ namespace`);
			current = { name, anchor, level, body: [] };
			sections.push(current);
		}

		// A heading whose only content is more headings (a pure grouping header)
		// has no prose to summarise. Listing what it groups is what an index is
		// for — an empty summary would make the caller open the file to find out.
		for (let i = 0; i < sections.length; i++) {
			const s = sections[i];
			s.summary = firstContentLine(s.body);
			if (s.summary) continue;
			const kids = [];
			for (let j = i + 1; j < sections.length && sections[j].level > s.level; j++)
				if (sections[j].level === s.level + 1) kids.push(sections[j].name);
			if (kids.length) s.summary = `Subsections: ${kids.join(" · ")}`;
		}

		const entry = {
			__title: title || file.replace(/\.md$/, ""),
			__bytes: Buffer.byteLength(text, "utf8"),
		};
		for (const s of sections) {
			// Two sections with the same NAME in one file would collide as object
			// keys; their anchors already differ (`-1`, `-2`), so key the later
			// ones by their anchor to keep both reachable.
			const key = entry[s.name] === undefined && !s.name.startsWith("__") ? s.name : s.anchor;
			entry[key] = { summary: s.summary, anchor: s.anchor };

			// Punctuation trap: GitHub deletes an em dash / slash / colon and then
			// hyphenates EACH remaining space, so `## Envelope 1 — RECON` slugs to
			// `envelope-1--recon` with a DOUBLE hyphen. Everyone writing a ref by
			// hand types the single-hyphen form. That is not heading drift — the
			// heading is right and the intent is unambiguous — so the index carries
			// the collapsed form as a tolerated alias rather than letting a correct
			// reference resolve to nothing. A genuine rename still breaks both, which
			// is the drift this file exists to catch.
			const alias = s.anchor.replace(/-{2,}/g, "-").replace(/^-|-$/g, "");
			if (alias && alias !== s.anchor && entry[`${s.name} (alias)`] === undefined)
				entry[`${s.name} (alias)`] = {
					summary: `Tolerated alias for "${s.name}"; the exact GitHub slug is ${s.anchor}`,
					anchor: alias,
				};
		}
		index[path] = entry;
	}

	return { index, problems, count: files.length };
}

const { index, problems, count } = buildIndex();
if (problems.length) {
	for (const p of problems) console.error(`FAIL ${p}`);
	process.exit(1);
}

const out = `${JSON.stringify(index, null, 2)}\n`;
const target = join(KDIR, "index.json");

if (process.argv.includes("--check")) {
	let current = "";
	try {
		current = readFileSync(target, "utf8");
	} catch {
		/* missing counts as different */
	}
	if (current !== out) {
		console.error(
			`FAIL ${posix(target)} is out of date — run \`node scripts/build-knowledge-index.mjs\``,
		);
		process.exit(1);
	}
	console.log(`knowledge index up to date (${count} files).`);
	process.exit(0);
}

writeFileSync(target, out);
const sections = Object.values(index).reduce((n, e) => n + Object.keys(e).length - 2, 0);
console.log(`Wrote ${posix(target)}: ${count} files, ${sections} sections.`);
