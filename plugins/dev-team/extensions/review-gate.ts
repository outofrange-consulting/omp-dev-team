// review-gate.ts — blocks `git commit` until the current staged set has been
// approved by a review pass. Port of the Claude Code `pre-commit-review.sh`
// PreToolUse gate (the "blocking" review hook).
//
// Flow:
//   1. Agent (or human) stages files and tries `git commit`.
//   2. This gate computes a hash of the staged file list + diff and compares it
//      to the last approved hash in .omp/state/review-gate.json.
//   3. If they differ (or none recorded), the commit is BLOCKED with guidance
//      to run /code-review, then /review-approve.
//   4. /review-approve records the current staged hash, unlocking that commit.
//
// Bypass: a commit command containing `--no-verify` is allowed (explicit human
// override, mirroring git's own semantics) but logged with a warning.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readState, writeState } from "./lib/shared.ts";

interface GateState {
	approvedHash?: string;
	approvedAt?: string;
}

function stagedHash(cwd: string): { hash: string; files: string[] } | null {
	try {
		const files = execSync("git diff --cached --name-only", {
			cwd,
			encoding: "utf8",
		})
			.split("\n")
			.map((s) => s.trim())
			.filter(Boolean);
		if (files.length === 0) return null;
		const diff = execSync("git diff --cached", { cwd, encoding: "utf8" });
		const hash = createHash("sha256").update(diff).digest("hex").slice(0, 16);
		return { hash, files };
	} catch {
		return null;
	}
}

function isGitCommit(cmd: string): boolean {
	return /\bgit\b[^&|;]*\bcommit\b/.test(cmd);
}

// Detect `--no-verify` only as a real argument token, not as a substring of the
// command (e.g. a commit MESSAGE containing the text "--no-verify"). We tokenize
// the command in a quote-aware way (so a quoted `-m '... --no-verify ...'`
// message stays a single token) and skip the value of a message flag
// (`-m VALUE`, `--message`, `-F FILE`, `--file`) so message bodies can't
// trigger the bypass.
function tokenizeShell(cmd: string): string[] {
	const tokens: string[] = [];
	const re = /'[^']*'|"[^"]*"|\S+/g;
	let m: RegExpExecArray | null;
	while ((m = re.exec(cmd)) !== null) tokens.push(m[0]);
	return tokens;
}

function hasNoVerifyFlag(cmd: string): boolean {
	const tokens = tokenizeShell(cmd);
	const skipNext = new Set(["-m", "--message", "-F", "--file"]);
	for (let i = 0; i < tokens.length; i++) {
		const tok = tokens[i];
		// `--message=...` / `--file=...` carry their value inline — skip whole token.
		if (/^--(?:message|file)=/.test(tok)) continue;
		if (skipNext.has(tok)) {
			i++; // skip this flag's value token
			continue;
		}
		if (tok === "--no-verify") return true;
	}
	return false;
}

export default function reviewGate(pi: ExtensionAPI) {
	pi.setLabel("review-gate");

	pi.registerCommand("review-approve", {
		description: "Record the current staged set as review-approved (unlocks commit)",
		handler: async (_args, ctx) => {
			const staged = stagedHash(ctx.cwd);
			if (!staged) {
				ctx.ui.notify("nothing staged to approve", "warn");
				return;
			}
			writeState(ctx.cwd, "review-gate.json", {
				approvedHash: staged.hash,
				approvedAt: new Date().toISOString(),
			} satisfies GateState);
			ctx.ui.notify(
				`review approved for ${staged.files.length} staged file(s) — commit unlocked`,
				"info",
			);
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return;
		const cmd = String(
			(event.input as Record<string, unknown>).command ?? "",
		);
		if (!isGitCommit(cmd)) return;
		if (hasNoVerifyFlag(cmd)) {
			ctx.ui.notify("commit with --no-verify: review gate bypassed", "warn");
			return;
		}
		const staged = stagedHash(ctx.cwd);
		if (!staged) return; // nothing staged; let git report it

		const state = readState<GateState>(ctx.cwd, "review-gate.json", {});
		if (state.approvedHash === staged.hash) return; // approved

		return {
			block: true,
			reason:
				`Commit blocked by review gate: the ${staged.files.length} staged file(s) ` +
				`have not passed review.\n` +
				`Run /code-review (or /skill:code-review) on the staged changes, then ` +
				`/review-approve to unlock this commit. To override explicitly, commit ` +
				`with --no-verify.`,
		};
	});
}
