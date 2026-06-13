// path-guard.ts — blocks writes/edits to secrets & sensitive files.
// Port of the Claude Code `pre-tool-guard.sh` hook + `guards.json`.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { matchesAny, pathsFromToolInput } from "./lib/shared.ts";

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

const WARN = [".omp/config.yml", ".omp/settings.json", "*.tfstate"];

export default function pathGuard(pi: ExtensionAPI) {
	pi.setLabel("path-guard");

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") return;
		const paths = pathsFromToolInput(
			event.toolName,
			event.input as Record<string, unknown>,
		);
		for (const p of paths) {
			const base = p.split("/").pop() ?? p;
			const blocked = matchesAny(p, BLOCKED) ?? matchesAny(base, BLOCKED);
			if (blocked) {
				return {
					block: true,
					reason:
						`Blocked write to sensitive path "${p}" (matches "${blocked}"). ` +
						`Editing secrets/credentials via the agent is denied. If this is a ` +
						`template or fixture, rename it or adjust path-guard.ts.`,
				};
			}
		}
		for (const p of paths) {
			const warn = matchesAny(p, WARN);
			if (warn) {
				ctx.ui.notify(
					`editing protected config "${p}" (${warn}) — double-check the change`,
					"warn",
				);
			}
		}
	});
}
