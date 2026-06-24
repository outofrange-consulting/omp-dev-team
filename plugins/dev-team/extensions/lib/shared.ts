// Shared helpers for omp-dev-team extensions.
// Lives in a subdirectory so OMP's top-level extension discovery does not treat
// it as an entry; the no-op default export below also makes it harmless if it is.

import {
	existsSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
	appendFileSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Resolve the package root (the `.omp` dir in workspace mode, or the plugin
// cache root when installed via the marketplace) from this module's own
// location, so agent/config lookups work regardless of the consuming
// project's cwd. shared.ts lives at <pkg>/extensions/lib/shared.ts.
const PKG_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

// --- Guard state location -------------------------------------------------
// Enforcement guards (freeze, careful, review-gate) must not keep their state
// where the agent they constrain can rewrite it. The old location was the
// project's own `.omp/state/` — editable by the very actor it restricts
// (`echo '{"globs":[]}' > .omp/state/freeze.json`). State now lives OUTSIDE the
// working tree by default, keyed per-repo, so a casual in-repo write no longer
// flips a guard off. Override with OMP_DEVTEAM_STATE_DIR. A read fallback to the
// legacy in-tree path keeps any pre-existing state working after the move.
//
// Honesty: this removes the in-tree footgun and casual self-override; it is not
// a hard sandbox — an agent that can run arbitrary shell could still reach the
// out-of-tree dir if it discovers the path. These guards are advisory-grade
// enforcement, not a security boundary (see the operating manual).
export const LEGACY_STATE_DIR = ".omp/state";

function repoId(cwd: string): string {
	let root = cwd;
	try {
		root = execFileSync("git", ["rev-parse", "--show-toplevel"], {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim() || cwd;
	} catch {
		root = cwd;
	}
	return createHash("sha256").update(root).digest("hex").slice(0, 16);
}

export function stateDir(cwd: string): string {
	const override = process.env.OMP_DEVTEAM_STATE_DIR;
	if (override && override.trim()) return join(override.trim(), repoId(cwd));
	return join(homedir(), ".omp", "state", "dev-team", repoId(cwd));
}

export function legacyStateDir(cwd: string): string {
	return join(cwd, LEGACY_STATE_DIR);
}

export function statePath(cwd: string, name: string): string {
	return join(stateDir(cwd), name);
}

// Read guard state from the relocated dir, falling back to the legacy in-tree
// path so state written before the relocation still applies.
export function readState<T>(cwd: string, name: string, fallback: T): T {
	const primary = statePath(cwd, name);
	if (existsSync(primary)) return readJSON<T>(primary, fallback);
	const legacy = join(legacyStateDir(cwd), name);
	if (existsSync(legacy)) return readJSON<T>(legacy, fallback);
	return fallback;
}

// Write guard state to the relocated (out-of-tree) dir.
export function writeState(cwd: string, name: string, data: unknown): void {
	writeJSON(statePath(cwd, name), data);
}

export function ensureDir(p: string): void {
	mkdirSync(dirname(p), { recursive: true });
}

export function readJSON<T>(path: string, fallback: T): T {
	try {
		if (!existsSync(path)) return fallback;
		return JSON.parse(readFileSync(path, "utf8")) as T;
	} catch {
		return fallback;
	}
}

export function writeJSON(path: string, data: unknown): void {
	ensureDir(path);
	writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`, "utf8");
}

export function appendJSONL(path: string, data: unknown): void {
	ensureDir(path);
	appendFileSync(path, `${JSON.stringify(data)}\n`, "utf8");
}

export function nowISO(): string {
	return new Date().toISOString();
}

// Extract target file path(s) from an OMP tool call's input.
//   write -> input.path
//   edit  -> ¶PATH#TAG headers inside input.input
export function pathsFromToolInput(
	toolName: string,
	input: Record<string, unknown>,
): string[] {
	if (toolName === "write" && typeof input.path === "string") {
		return [input.path];
	}
	if (toolName === "edit" && typeof input.input === "string") {
		const out: string[] = [];
		const re = /¶([^\n#]+)#[0-9A-Fa-f]{4}/g;
		let m: RegExpExecArray | null;
		while ((m = re.exec(input.input)) !== null) out.push(m[1].trim());
		return out;
	}
	return [];
}

// Read an agent's `model:` frontmatter value from <pkg>/agents/<name>.md.
export function agentModel(agentName: string): string | null {
	try {
		const file = join(PKG_ROOT, "agents", `${agentName}.md`);
		if (!existsSync(file)) return null;
		const text = readFileSync(file, "utf8");
		const fm = text.match(/^---\n([\s\S]*?)\n---/);
		if (!fm) return null;
		const line = fm[1].split("\n").find((l) => /^model:\s*/.test(l));
		return line ? line.replace(/^model:\s*/, "").trim() : null;
	} catch {
		return null;
	}
}

export interface RoutingTier {
	role?: string;
	frontmatter: string;
	intent: string;
	rationale: string;
}

export interface EffortBandConfig {
	ladder: string[];
	effort: Record<string, { shift: number; note?: string }>;
	protectDownshift: string[];
	enforcement?: string;
	biasUp?: boolean;
}

export interface RoutingConfig {
	tiers: Record<string, RoutingTier>;
	effortBand?: EffortBandConfig;
}

// Resolve the effective band for a base band + task size. Pure: no I/O.
//   - bands outside the ladder (default/pinned) are returned unchanged
//   - a base in protectDownshift never shifts DOWN (safety agents)
//   - the shifted index is clamped to the ladder ends
export function effectiveBand(
	base: string,
	size: string | undefined,
	cfg: EffortBandConfig | undefined,
): string {
	if (!cfg || !Array.isArray(cfg.ladder)) return base;
	const i = cfg.ladder.indexOf(base);
	if (i === -1) return base; // default/pinned — not on the ladder
	const shift = cfg.effort?.[size ?? "standard"]?.shift ?? 0;
	if (shift < 0 && cfg.protectDownshift?.includes(base)) return base;
	const j = Math.max(0, Math.min(cfg.ladder.length - 1, i + shift));
	return cfg.ladder[j];
}

export function loadRouting(): RoutingConfig | null {
	const p = join(PKG_ROOT, "skills", "dev-team-knowledge", "model-routing.json");
	return readJSON<RoutingConfig | null>(p, null);
}

// Simple glob -> RegExp (supports * and **, and a leading-dir match).
// Case-insensitive on purpose: path/secret matching must treat `ID_RSA`,
// `.PEM`, `Secret.txt` as matching `id_rsa`/`*.pem`/`*secret*` (macOS/Windows
// treat these as the same files). Only used for path matching by path-guard
// and freeze-guard, both of which want case-insensitivity.
export function globToRegExp(glob: string): RegExp {
	const esc = glob
		.replace(/[.+^${}()|[\]\\]/g, "\\$&")
		.replace(/\*\*/g, "\u0000")
		.replace(/\*/g, "[^/]*")
		.replace(/\u0000/g, ".*");
	return new RegExp(`(^|/)${esc}$`, "i");
}

export function matchesAny(value: string, globs: string[]): string | null {
	for (const g of globs) {
		if (globToRegExp(g).test(value)) return g;
	}
	return null;
}

// Best-effort extraction of likely write *targets* from a shell command, so the
// path/freeze guards can catch writes performed via the shell rather than the
// write/edit tools. This is advisory: it parses common forms with regexes, not
// a real shell, so unusual quoting/expansion can slip through. Covered forms:
//   redirections        cmd > FILE   /  cmd >> FILE
//   tee                 ... | tee FILE [FILE...]
//   in-place sed        sed -i ... FILE
//   copy / move dest    cp SRC DEST  /  mv SRC DEST  (last token is the dest)
export function bashWriteTargets(cmd: string): string[] {
	const out: string[] = [];
	const add = (s: string | undefined | null) => {
		if (!s) return;
		const t = s.replace(/^['"]|['"]$/g, "").trim();
		if (t && !t.startsWith("-")) out.push(t);
	};

	// Redirections: > FILE / >> FILE (ignore fd-dup like >&2, and /dev targets
	// are still surfaced — the guard globs decide what's sensitive).
	const redir = /(?:^|[^>\d])>>?\s*([^\s;|&><]+)/g;
	let m: RegExpExecArray | null;
	while ((m = redir.exec(cmd)) !== null) {
		if (m[1].startsWith("&")) continue;
		add(m[1]);
	}

	// tee [-a] FILE [FILE...]
	const tee = /\btee\b((?:\s+-\S+)*)\s+([^\n;|&]+)/g;
	while ((m = tee.exec(cmd)) !== null) {
		for (const tok of m[2].split(/\s+/)) {
			if (tok === "|" || tok === "&&" || tok === "||") break;
			add(tok);
		}
	}

	// sed -i ... FILE  (in-place edit; targets are the trailing file args)
	const sed = /\bsed\b\s+(?:-\S+\s+|--\S+(?:=\S+)?\s+|(?:'[^']*'|"[^"]*"|\S+)\s+)*-i\S*\s+([^\n;|&]+)/g;
	while ((m = sed.exec(cmd)) !== null) {
		for (const tok of m[1].split(/\s+/)) {
			// skip the sed script (quoted) and option-looking tokens
			if (/^['"]/.test(tok) || tok.startsWith("-")) continue;
			add(tok);
		}
	}

	// cp/mv SRC... DEST — the final non-flag token is the destination.
	const cpmv = /\b(?:cp|mv)\b\s+([^\n;|&]+)/g;
	while ((m = cpmv.exec(cmd)) !== null) {
		const toks = m[1].split(/\s+/).filter((t) => t && !t.startsWith("-"));
		if (toks.length >= 2) add(toks[toks.length - 1]);
	}

	return out;
}

export { resolve };

// Harmless default export in case discovery picks this file up as an entry.
export default function () {}
