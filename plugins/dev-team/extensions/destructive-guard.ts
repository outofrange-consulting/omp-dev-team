// destructive-guard.ts — warns on (or, in careful mode, blocks) destructive
// shell commands. Port of the Claude Code `destructive-guard.sh` hook +
// `destructive-commands.json`.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { readJSON, statePath } from "./lib/shared.ts";

const PATTERNS: Array<[string, string[]]> = [
	["File destruction", ["rm -rf", "rm -r ", "rm -fr", "rm -f /"]],
	["Database destruction", ["drop table", "drop database", "truncate "]],
	[
		"Git destruction",
		[
			"git push --force",
			"git push -f",
			"git reset --hard",
			"git clean -f",
			"git checkout -- .",
			"git branch -d",
		],
	],
	["Process destruction", ["kill -9", "killall", "pkill"]],
	["Permission escalation", ["chmod 777", "chmod -r 777"]],
	["Disk", ["mkfs", "dd if=", "> /dev/sd"]],
];

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

export default function destructiveGuard(pi: ExtensionAPI) {
	pi.setLabel("destructive-guard");

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return;
		const cmd = String(
			(event.input as Record<string, unknown>).command ?? "",
		);
		if (!cmd) return;
		const lower = cmd.toLowerCase();

		if (SAFE.some((s) => lower.includes(s))) return;

		let match = "";
		for (const [category, pats] of PATTERNS) {
			const hit = pats.find((p) => lower.includes(p));
			if (hit) {
				match = `${category}: ${hit}`;
				break;
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
