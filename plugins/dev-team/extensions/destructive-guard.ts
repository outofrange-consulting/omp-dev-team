// destructive-guard.ts — the unified dev-team destructive-command guard.
//
// Two tiers:
//   DENY  — catastrophic, UNRECOVERABLE commands are blocked outright, always,
//           regardless of careful mode (fork bombs; recursive rm of / ~ /* $HOME;
//           rm --no-preserve-root). Ported from serena-forge's protect-commands.sh.
//   WARN/ — destructive-but-recoverable commands (git force/reset/clean, rm -rf on
//   CAREFUL a path, DB DROP/TRUNCATE, `dotnet ef database drop`, unqualified SQL
//           DELETE/UPDATE, …) warn by default and hard-block only under /careful.
//
// This merges the original Claude Code `destructive-guard.sh` set with the
// serena-forge `protect-commands.sh` set into ONE guard (serena-forge is now part
// of dev-team, so the old two-hook coexistence — and its duplicate CAUTION line —
// is gone). The DENY tier is the one behavior change from the pre-merge guard:
// the truly catastrophic root/home wipes and fork bombs now block unconditionally
// instead of merely warning.
//
// NOTE: detection is best-effort / advisory. It does NOT parse the shell — it
// matches normalized command text with a small set of regexes, scoped per shell
// segment so a keyword/target in one chained command can neither trigger nor
// suppress a rule on a sibling. The goal is to catch obvious dangerous forms, not
// to be an exhaustive, bypass-proof gate.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { readState } from "./lib/shared.ts";

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

// `rm` with a recursive flag (force NOT required) — used for the catastrophic
// DENY tier, where `rm -r /` is refused even without -f.
function isRmRecursive(seg: string): boolean {
	if (!/\brm\b/i.test(seg)) return false;
	for (const tok of seg.split(" ")) {
		if (tok === "--recursive") return true;
		if (/^-[a-z]+$/i.test(tok) && /r/i.test(tok)) return true;
	}
	return false;
}

// --- Catastrophic (DENY) targets, matched within the SAME segment as the rm ---
const CAT_ROOT = /(^|\s)\/(\s|$)/; //  " / "   filesystem root
const CAT_ROOTGLOB = /(^|\s)\/\*/; //  " /* "  root contents
const CAT_HOME = /(^|\s)~\/?(\s|$)/; //  " ~ " or " ~/ "  home root
const CAT_HOMEENV = /\$\{?home\}?(?![a-z0-9_/])/i; // $HOME / ${HOME} (not $HOME/sub)
const CAT_NOPRESERVE = /--no-preserve-root/i;

// Fork bomb: a function whose body pipes a BARE call to a BARE call and
// backgrounds it, e.g. :(){ :|:& };:  or  bomb(){ bomb|bomb& }. The bare
// identifiers around the pipe are what make it self-replicating.
const FORKBOMB = /\(\)\s*\{[^}]*[a-z_:][a-z0-9_:]*\s*\|\s*[a-z_:][a-z0-9_:]*\s*&/i;

// A segment is catastrophic if it is a recursive rm whose OWN segment names a
// root/home target, or any rm carrying --no-preserve-root.
function isCatastrophicSegment(seg: string): boolean {
	const lower = seg.toLowerCase();
	if (/\brm\b/i.test(seg) && CAT_NOPRESERVE.test(seg)) return true;
	if (
		isRmRecursive(seg) &&
		(CAT_ROOT.test(seg) ||
			CAT_ROOTGLOB.test(seg) ||
			CAT_HOME.test(seg) ||
			CAT_HOMEENV.test(lower))
	)
		return true;
	return false;
}

// [category, regexes] — each regex runs against a single normalized segment.
// These are the WARN/CAREFUL tier (destructive but recoverable).
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
	[
		"Database destruction",
		[
			/\bdrop\s+(?:table|database|schema|view|index)\b/i,
			/\btruncate\s+table\b/i,
			/\bdotnet\s+ef\s+database\s+drop\b/i,
		],
	],
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

// Unqualified SQL mutations: DELETE/UPDATE with no WHERE clause in the SAME
// segment affect every row. Handled specially (a negative WHERE lookahead is
// clearer as code than as a single regex).
const SQL_DELETE = /\bdelete\s+from\b/i;
const SQL_UPDATE = /\bupdate\s+\S+[\s\S]*\bset\b/i;
const SQL_WHERE = /\bwhere\b/i;

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

		const segs = segments(cmd);

		// ---- DENY tier: catastrophic, unrecoverable — always block ----------
		let deny = "";
		if (FORKBOMB.test(normalize(cmd))) {
			deny = "fork bomb";
		} else {
			for (const seg of segs) {
				if (isSafeSegment(seg)) continue;
				if (isCatastrophicSegment(seg)) {
					deny = `recursive delete of a root/home path — ${seg}`;
					break;
				}
			}
		}
		if (deny) {
			return {
				block: true,
				reason:
					`REFUSED (catastrophic): ${deny}.\n` +
					`Command: ${cmd}\n` +
					`This is denied outright and is not overridable in-agent (not even with /careful off) — ` +
					`it destroys the filesystem root, the home directory, or the machine. ` +
					`If this is genuinely intended, run it yourself, outside the agent.`,
			};
		}

		// ---- WARN / CAREFUL tier: destructive but recoverable ---------------
		// Evaluate each segment independently; a safe segment is skipped but never
		// suppresses checks on its siblings.
		let match = "";
		outer: for (const seg of segs) {
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
			// Unqualified SQL mutation (no WHERE in this segment).
			if (SQL_DELETE.test(seg) && !SQL_WHERE.test(seg)) {
				match = `Database destruction (DELETE without WHERE): ${seg}`;
				break;
			}
			if (SQL_UPDATE.test(seg) && !SQL_WHERE.test(seg)) {
				match = `Database destruction (UPDATE without WHERE): ${seg}`;
				break;
			}
		}
		if (!match) return;

		const careful = readState<{ active: boolean }>(
			ctx.cwd,
			"careful.json",
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
			"warning",
		);
	});
}
