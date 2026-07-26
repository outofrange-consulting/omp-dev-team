// review-gate.ts — blocks `git commit` until the current staged set has been
// approved by a review pass. Port of the Claude Code `pre-commit-review.sh`
// PreToolUse gate (the "blocking" review hook).
//
// Flow:
//   1. Agent (or human) stages files and tries `git commit`.
//   2. This gate computes a hash of the staged file list + diff and compares it
//      to the last approved hash in review-gate.json (out-of-tree state dir,
//      see lib/shared.ts).
//   3. If they differ (or none recorded), the commit is BLOCKED with guidance
//      to run /code-review, then /review-approve.
//   4. /review-approve records the current staged hash, unlocking that commit.
//
// Bypass: `--no-verify` still overrides the gate (mirroring git's own
// semantics), but it is no longer free. It must carry a non-empty reason and it
// leaves a durable audit line. Upstream ADR-0006 measured bypassing as
// correlating with ~2.6x rework, so a bypass is a decision worth recording, not
// a keystroke: an unexplained one blocks, and every accepted one is written to
// review-gate-bypass.jsonl next to the gate state (out of the working tree, so
// the actor being constrained cannot quietly delete it with a file edit).

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { appendJSONL, nowISO, readState, statePath, writeState } from "./lib/shared.ts";

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

const BYPASS_REASON_VAR = "GATE_BYPASS_REASON";

// Where the bypass reason may come from. Two callers, two mechanisms:
//   - a human exports GATE_BYPASS_REASON in the shell that launched OMP, so it
//     is visible in this process's env;
//   - an agent cannot touch this process's env, but it can write the assignment
//     as a command prefix (`GATE_BYPASS_REASON="..." git commit --no-verify`),
//     which we read straight off the command string.
// Honesty: the actor supplies its own reason, so the text is NOT a
// justification we verified — its value is accountability. An unexplained
// bypass blocks; an explained one is recorded and traceable afterwards.
function bypassReason(cmd: string): { reason: string; source: "command" | "env" } | null {
	const inline = inlineAssignment(cmd, BYPASS_REASON_VAR);
	if (inline) return { reason: inline, source: "command" };
	const env = (process.env[BYPASS_REASON_VAR] ?? "").trim();
	if (env) return { reason: env, source: "env" };
	return null;
}

// Find `NAME=value` where the assignment itself sits OUTSIDE any quoted string,
// then read its (possibly quoted) value. Scanning quote state rather than
// regex-matching the whole command is what stops a commit MESSAGE that merely
// mentions `GATE_BYPASS_REASON=...` from satisfying the requirement — the same
// class of hole hasNoVerifyFlag() already closes for the flag itself.
function inlineAssignment(cmd: string, name: string): string | null {
	const needle = `${name}=`;
	let quote: string | null = null;
	for (let i = 0; i < cmd.length; i++) {
		const c = cmd[i];
		if (quote) {
			if (c === quote) quote = null;
			continue;
		}
		if (c === "'" || c === '"') {
			quote = c;
			continue;
		}
		if (!cmd.startsWith(needle, i)) continue;
		// Must start a token: preceded by nothing, whitespace, or a separator.
		const prev = i === 0 ? "" : cmd[i - 1];
		if (prev !== "" && !/[\s;|&(]/.test(prev)) continue;
		let j = i + needle.length;
		const q = cmd[j];
		if (q === "'" || q === '"') {
			const end = cmd.indexOf(q, j + 1);
			if (end === -1) return null; // unterminated quote — treat as absent
			const value = cmd.slice(j + 1, end).trim();
			return value || null;
		}
		while (j < cmd.length && !/[\s;|&]/.test(cmd[j])) j++;
		const value = cmd.slice(i + needle.length, j).trim();
		return value || null;
	}
	return null;
}

function currentBranch(cwd: string): string {
	try {
		return execSync("git branch --show-current", {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
	} catch {
		return "";
	}
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
				ctx.ui.notify("nothing staged to approve", "warning");
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
			// ADR-0006's gate-correlation evidence: commits that bypassed the
			// review gate carried ~2.6x the rework of commits that did not. A
			// bypass is therefore a decision worth recording — not free.
			const supplied = bypassReason(cmd);
			if (!supplied) {
				return {
					block: true,
					reason:
						`Commit blocked: \`--no-verify\` bypasses the review gate and requires a reason.\n` +
						`Upstream's gate-correlation measurement (ADR-0006) found bypassed commits ` +
						`carried ~2.6x the rework of reviewed ones, so the bypass is recorded, not silent.\n\n` +
						`Retry with the reason inline:\n` +
						`  ${BYPASS_REASON_VAR}="hotfix, review to follow" git commit --no-verify -m ...\n\n` +
						`(A human can instead export ${BYPASS_REASON_VAR} in the shell that launched OMP.)\n` +
						`Prefer the gate: run /code-review on the staged changes, then /review-approve.`,
				};
			}
			const bypassStaged = stagedHash(ctx.cwd);
			// Durable, out-of-tree next to the gate state, so the actor being
			// constrained cannot quietly drop it with a file edit. Fail-open by
			// construction: appendJSONL throwing must never brick a commit.
			try {
				appendJSONL(statePath(ctx.cwd, "review-gate-bypass.jsonl"), {
					ts: nowISO(),
					guard: "review-gate",
					decision: "bypass",
					trigger: "--no-verify",
					branch: currentBranch(ctx.cwd),
					stagedFileCount: bypassStaged?.files.length ?? 0,
					stagedHash: bypassStaged?.hash ?? null,
					reasonSource: supplied.source,
					reason: supplied.reason,
				});
			} catch {
				// audit write failed; the notify below is still the visible record
			}
			ctx.ui.notify(
				`review gate bypassed (--no-verify) — recorded: ${supplied.reason}`,
				"warning",
			);
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
				`with --no-verify AND a reason: ` +
				`${BYPASS_REASON_VAR}="why" git commit --no-verify -m ... (the bypass is ` +
				`recorded to review-gate-bypass.jsonl).`,
		};
	});
}
