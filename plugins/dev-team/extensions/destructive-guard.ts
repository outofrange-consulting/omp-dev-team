// destructive-guard.ts — warns on (or, in careful mode, blocks) destructive
// shell commands. Port of the Claude Code `destructive-guard.sh` hook +
// `destructive-commands.json`.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { readJSON, statePath } from "./lib/shared.ts";

// NOTE: destructive-command detection here is best-effort / advisory. It does
// NOT parse the shell — it matches normalized command text with a small set of
// regexes. The goal is to catch obvious dangerous forms (and their common
// flag/whitespace variants), not to be an exhaustive, bypass-proof gate.

// `rm` with BOTH recursive and force flags, in any order / spelling: combined
// (-rf, -fr), separated (-r -f, -f -r), and long (--recursive --force, either
// order). We look at a single normalized segment that starts with `rm`, collect
// its short/long option flags, and require a recursive flag AND a force flag.
function isRmRecursiveForce(seg: string): boolean {
	if (!/\brm\b/i.test(seg)) return false;
	let recursive = false;
	let force = false;
	for (const tok of seg.split(" ")) {
		if (tok === "--recursive") recursive = true;
		else if (tok === "--force") force = true;
		else if (/^-[a-z]+$/i.test(tok)) {
			// combined short flags, e.g. -rf, -fr, -rfv
			if (/r/i.test(tok)) recursive = true;
			if (/f/i.test(tok)) force = true;
		}
	}
	return recursive && force;
}

// [category, regexes] — each regex runs against a single normalized segment.
const PATTERNS: Array<[string, RegExp[]]> = [
	[
		"File destruction",
		[
			/\brm\b\s+(?:-\S+\s+)*\/(?:\s|$)/i, // rm ... /  (root-ish target)
			/\bfind\b[^\n]*\s-delete\b/i,
			/\bshred\b/i,
			/\btruncate\b\s+(?:-s\s*0|--size[= ]0)\b/i,
		],
	],
	["Database destruction", [/\bdrop\s+table\b/i, /\bdrop\s+database\b/i, /\btruncate\s+table\b/i]],
	[
		"Git destruction",
		[
			/\bgit\s+push\s+(?:[^\n]*\s)?(?:--force\b|-f\b)/i,
			/\bgit\s+reset\s+--hard\b/i,
			/\bgit\s+clean\s+-[a-z]*f[a-z]*d|git\s+clean\s+-[a-z]*d[a-z]*f|git\s+clean\s+(?:[^\n]*\s)?-f\b/i,
			/\bgit\s+checkout\s+--\s+\.|git\s+checkout\s+--\s*$/i,
			/\bgit\s+branch\s+-D\b/i,
		],
	],
	["Process destruction", [/\bkill\s+-9\b/i, /\bkillall\b/i, /\bpkill\b/i]],
	["Permission escalation", [/\bchmod\s+(?:-R\s+)?0?777\b/i]],
	["Disk", [/\bmkfs\b/i, /\bdd\s+if=/i, />\s*\/dev\/sd/i]],
];

// SAFE entries name the *operative command* of a segment. A segment is safe only
// if, after whitespace normalization, it equals one of these (optionally with a
// trailing path under the named directory) — not merely contains it.
const SAFE = [
	"rm -rf node_modules",
	"rm -rf dist",
	"rm -rf build",
	"rm -rf .cache",
	"rm -rf coverage",
	"rm -rf tmp",
	"rm -rf __pycache__",
	"rm -rf .next",
	"rm -rf target/debug",
];

// Normalize a command: collapse whitespace runs to single spaces, trim.
function normalize(s: string): string {
	return s.replace(/\s+/g, " ").trim();
}

// Split a command line into independently-evaluated segments on shell control
// operators so a safe segment can never suppress checks on a sibling segment.
function segments(cmd: string): string[] {
	return cmd
		.split(/&&|\|\||;|\||\n/)
		.map((s) => normalize(s))
		.filter(Boolean);
}

// A segment is "safe" only if its operative command is `rm` of a known-safe
// directory (and optionally a subpath under it) with ONLY recursive/force flags.
// Flag spelling is normalized (-rf, -fr, -r -f all OK) but extra targets are not
// allowed — so a sibling like `rm -rf /etc` is never made safe by a safe sibling.
function isSafeSegment(seg: string): boolean {
	const lower = seg.toLowerCase();
	const parts = lower.split(" ");
	if (parts[0] !== "rm") return false;
	let i = 1;
	while (i < parts.length && parts[i].startsWith("-")) {
		// only recursive/force flags are tolerated in a "safe" segment
		const flag = parts[i];
		if (flag !== "--recursive" && flag !== "--force" && !/^-[rf]+$/.test(flag))
			return false;
		i++;
	}
	const targets = parts.slice(i);
	if (targets.length !== 1) return false; // exactly one target
	const target = targets[0].replace(/^\.\//, "").replace(/\/$/, "");
	return SAFE.some((s) => {
		const dir = s.slice("rm -rf ".length);
		return target === dir || target.startsWith(`${dir}/`);
	});
}

export default function destructiveGuard(pi: ExtensionAPI) {
	pi.setLabel("destructive-guard");

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return;
		const cmd = String(
			(event.input as Record<string, unknown>).command ?? "",
		);
		if (!cmd) return;

		// Evaluate each segment independently; a safe segment is skipped but never
		// suppresses checks on its siblings.
		let match = "";
		outer: for (const seg of segments(cmd)) {
			if (isSafeSegment(seg)) continue;
			if (isRmRecursiveForce(seg)) {
				match = `File destruction: ${seg}`;
				break;
			}
			for (const [category, pats] of PATTERNS) {
				const hit = pats.find((p) => p.test(seg));
				if (hit) {
					match = `${category}: ${seg}`;
					break outer;
				}
			}
		}
		if (!match) return;

		const careful = readJSON<{ active: boolean }>(
			statePath(ctx.cwd, "careful.json"),
			{ active: false },
		).active;

		if (careful) {
			return {
				block: true,
				reason:
					`BLOCKED (careful mode): destructive command detected (${match}).\n` +
					`Command: ${cmd}\n` +
					`Run /careful off to disable, or confirm with the user first.`,
			};
		}
		ctx.ui.notify(
			`CAUTION: destructive command (${match}) — hard to reverse. Confirm with the user.`,
			"warn",
		);
	});
}
