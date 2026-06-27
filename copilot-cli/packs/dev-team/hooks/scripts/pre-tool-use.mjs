#!/usr/bin/env node
// pre-tool-use.mjs — the dev-team blocking guard, as a single Copilot CLI
// `preToolUse` hook. Evaluates every guard and denies on the first hit:
//
//   path-guard         block writes to secrets/credentials (.env, *.pem, ...)
//   freeze-guard       block edits to /freeze'd path globs (set via `dt freeze`)
//   spec-guard         block edits to existing .feature BDD specs
//   destructive-guard  block destructive shell cmds in careful mode (warn otherwise)
//   review-gate        block `git commit` until the staged set is review-approved
//   plan-gate          block source edits until scoped (-> trivial | plan-approved)
//
// Mutating state (scope, approvals, freeze, careful) is driven by the `dt` CLI,
// since Copilot CLI has no user-defined slash commands. Ported from the OMP
// dev-team extensions (path-guard.ts, freeze-guard.ts, spec-guard.ts,
// destructive-guard.ts, review-gate.ts, plan-gate.ts).

import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
	readPayload,
	allow,
	deny,
	readState,
	isShellTool,
	isWriteTool,
	commandFromArgs,
	pathsFromArgs,
	bashWriteTargets,
	matchesAny,
	fileExists,
} from "./common.mjs";

const p = readPayload();
const cwd = p.cwd;
const isShell = isShellTool(p.toolName);
const isWrite = isWriteTool(p.toolName);
const cmd = isShell ? commandFromArgs(p.toolArgs) : "";
const writePaths = isWrite ? pathsFromArgs(p.toolArgs) : [];
const shellTargets = isShell && cmd ? bashWriteTargets(cmd) : [];
// All file paths this call could write to, via either the file tools or the shell.
const targets = [...writePaths, ...shellTargets];

// ============================== path-guard ==================================
const BLOCKED = [
	".env",
	".env.*",
	"*.pem",
	"*.key",
	"*.p12",
	"*.pfx",
	"*credential*",
	"*secret*",
	"*.token",
	"id_rsa",
	"id_ed25519",
];
for (const f of targets) {
	const base = f.split("/").pop() ?? f;
	const hit = matchesAny(f, BLOCKED) ?? matchesAny(base, BLOCKED);
	if (hit) {
		deny(
			`path-guard: blocked write to sensitive path "${f}" (matches "${hit}"). ` +
				`Writing secrets/credentials via the agent is denied. If this is a ` +
				`template or fixture, rename it.`,
		);
	}
}

// ============================== freeze-guard ================================
const frozen = readState(cwd, "freeze.json", { globs: [] }).globs ?? [];
if (frozen.length) {
	for (const f of targets) {
		const g = matchesAny(f, frozen);
		if (g) {
			deny(
				`freeze-guard: "${f}" is frozen (matches "${g}"). Run \`dt unfreeze ${g}\` to edit it.`,
			);
		}
	}
}

// ============================== spec-guard ==================================
// Block edits to EXISTING .feature specs (fix the code, don't rewrite the test).
// Authoring a brand-new .feature is fine. Opt out with `dt allow-feature-edits`.
const allowFeatureEdits =
	/^(1|true|yes|on)$/i.test(process.env.ALLOW_FEATURE_EDITS ?? "") ||
	readState(cwd, "spec-guard.json", { allow: false }).allow === true;
if (!allowFeatureEdits) {
	const featureReason = (path) =>
		`spec-guard: blocked edit of BDD spec "${path}". Fix the CODE to satisfy the ` +
		`spec — don't change the test to make it pass. If the spec itself is wrong, ` +
		`change it deliberately (or \`dt allow-feature-edits\` for this session, then ` +
		`\`dt protect-features\`).`;
	for (const f of writePaths) {
		if (!/\.feature$/i.test(f)) continue;
		// A write tool only blocks an overwrite of an existing spec; a brand-new
		// spec is allowed. (We can't tell edit-vs-create reliably across tool
		// schemas, so gate on file existence.)
		if (fileExists(cwd, f)) deny(featureReason(f));
	}
	if (isShell && /\.feature\b/i.test(cmd)) {
		const BASH_WRITE_RE =
			/(>>?|\btee\b|sed\s+-i|\bmv\b|\bcp\b|\brm\b|\btruncate\b|\bdd\b|python\d?\s+-c|node\s+-e|perl\s+-[a-z]*i|\bed\b|git\s+checkout\s+--)/i;
		if (BASH_WRITE_RE.test(cmd)) deny(`${featureReason("(.feature via shell)")}\nCommand: ${cmd}`);
	}
}

// ============================== destructive-guard ===========================
// Upstream warns (advisory) by default and BLOCKS in careful mode. A Copilot CLI
// preToolUse hook can only allow/deny — it can't "warn and continue" — so we deny
// destructive commands ONLY in careful mode (`dt careful on`); outside it, the
// command falls through to Copilot CLI's own permission prompt.
if (isShell && cmd) {
	const careful = readState(cwd, "careful.json", { active: false }).active === true;
	if (careful) {
		const match = destructiveMatch(cmd);
		if (match) {
			deny(
				`destructive-guard (careful mode): destructive command detected (${match}).\n` +
					`Command: ${cmd}\nRun \`dt careful off\` to disable, or confirm with the user first.`,
			);
		}
	}
}

// ============================== review-gate =================================
if (isShell && cmd && isGitCommit(cmd) && !hasNoVerifyFlag(cmd)) {
	const staged = stagedHash(cwd);
	if (staged) {
		const state = readState(cwd, "review-gate.json", {});
		if (state.approvedHash !== staged.hash) {
			deny(
				`review-gate: commit blocked — the ${staged.files.length} staged file(s) ` +
					`have not passed review. Run the code-review agent on the staged changes, ` +
					`then \`dt review-approve\` to unlock this commit. To override, commit with --no-verify.`,
			);
		}
	}
}

// ============================== plan-gate ===================================
// Block edits to production SOURCE until scoped (-> trivial | plan-approved).
const SOURCE_RE =
	/\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|rb|php|cs|swift|scala|c|cc|cpp|h|hpp|m|mm|svelte|vue)$/i;
const TEST_RE = /(\.|_|\/)(test|spec)\.|(^|\/)(tests?|__tests__|spec)\//i;
const isGatedSource = (f) => SOURCE_RE.test(f) && !TEST_RE.test(f);
const gated = targets.filter(isGatedSource);
if (gated.length) {
	const stage = readState(cwd, "plan-gate.json", {}).stage;
	if (stage !== "trivial" && stage !== "plan-approved") {
		if (stage === "needs-plan") {
			deny(
				`plan-gate: this task is scoped NON-TRIVIAL — implementing source ("${gated[0]}") ` +
					`needs an approved plan. Draft it with the plan agent, get human sign-off, then ` +
					`\`dt plan-approve\` to unlock the build.`,
			);
		} else {
			deny(
				`plan-gate: editing source ("${gated[0]}") before pre-analysis. Pipeline order is ` +
					`enforced: scope -> (trivial | plan) -> build -> review. Run \`dt scope\` first ` +
					`(\`dt scope --trivial\` for a one-line/typo change; otherwise plan it, get sign-off, ` +
					`\`dt plan-approve\`). Docs, config, specs, and tests are never gated.`,
			);
		}
	}
}

allow();

// ============================== helpers =====================================
function isGitCommit(c) {
	return /\bgit\b[^&|;]*\bcommit\b/.test(c);
}
function tokenizeShell(c) {
	const tokens = [];
	const re = /'[^']*'|"[^"]*"|\S+/g;
	let m;
	while ((m = re.exec(c)) !== null) tokens.push(m[0]);
	return tokens;
}
function hasNoVerifyFlag(c) {
	const tokens = tokenizeShell(c);
	const skipNext = new Set(["-m", "--message", "-F", "--file"]);
	for (let i = 0; i < tokens.length; i++) {
		const tok = tokens[i];
		if (/^--(?:message|file)=/.test(tok)) continue;
		if (skipNext.has(tok)) {
			i++;
			continue;
		}
		if (tok === "--no-verify") return true;
	}
	return false;
}
function stagedHash(c) {
	try {
		const files = execSync("git diff --cached --name-only", { cwd: c, encoding: "utf8" })
			.split("\n")
			.map((s) => s.trim())
			.filter(Boolean);
		if (files.length === 0) return null;
		const diff = execSync("git diff --cached", { cwd: c, encoding: "utf8" });
		const hash = createHash("sha256").update(diff).digest("hex").slice(0, 16);
		return { hash, files };
	} catch {
		return null;
	}
}

function destructiveMatch(c) {
	const normalize = (s) => s.replace(/\s+/g, " ").trim();
	const segments = c
		.split(/&&|\|\||;|\||\n/)
		.map(normalize)
		.filter(Boolean);
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
	const isSafeSegment = (seg) => {
		const parts = seg.toLowerCase().split(" ");
		if (parts[0] !== "rm") return false;
		let i = 1;
		while (i < parts.length && parts[i].startsWith("-")) {
			const flag = parts[i];
			if (flag !== "--recursive" && flag !== "--force" && !/^-[rf]+$/.test(flag)) return false;
			i++;
		}
		const tgts = parts.slice(i);
		if (tgts.length !== 1) return false;
		const target = tgts[0].replace(/^\.\//, "").replace(/\/$/, "");
		return SAFE.some((s) => {
			const dir = s.slice("rm -rf ".length);
			return target === dir || target.startsWith(`${dir}/`);
		});
	};
	const isRmRecursiveForce = (seg) => {
		if (!/\brm\b/i.test(seg)) return false;
		let recursive = false;
		let force = false;
		for (const tok of seg.split(" ")) {
			if (tok === "--recursive") recursive = true;
			else if (tok === "--force") force = true;
			else if (/^-[a-z]+$/i.test(tok)) {
				if (/r/i.test(tok)) recursive = true;
				if (/f/i.test(tok)) force = true;
			}
		}
		return recursive && force;
	};
	const PATTERNS = [
		[
			"File destruction",
			[
				/\brm\b\s+(?:-\S+\s+)*\/(?:\s|$)/i,
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
	for (const seg of segments) {
		if (isSafeSegment(seg)) continue;
		if (isRmRecursiveForce(seg)) return `File destruction: ${seg}`;
		for (const [category, pats] of PATTERNS) {
			if (pats.find((re) => re.test(seg))) return `${category}: ${seg}`;
		}
	}
	return "";
}
