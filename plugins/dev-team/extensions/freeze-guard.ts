// freeze-guard.ts — /freeze and /unfreeze a set of path globs so the agent
// cannot modify them. Port of the Claude Code `/freeze` `/unfreeze` skills.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	bashWriteTargets,
	matchesAny,
	pathsFromToolInput,
	readJSON,
	statePath,
	writeJSON,
} from "./lib/shared.ts";

interface FreezeState {
	globs: string[];
}

function load(cwd: string): FreezeState {
	return readJSON<FreezeState>(statePath(cwd, "freeze.json"), { globs: [] });
}

export default function freezeGuard(pi: ExtensionAPI) {
	pi.setLabel("freeze-guard");

	pi.registerCommand("freeze", {
		description: "Lock path glob(s) against edits: /freeze <glob> [glob...]",
		handler: async (args, ctx) => {
			const globs = (args ?? "").trim().split(/\s+/).filter(Boolean);
			if (globs.length === 0) {
				const cur = load(ctx.cwd).globs;
				ctx.ui.notify(
					cur.length ? `frozen: ${cur.join(", ")}` : "nothing frozen",
					"info",
				);
				return;
			}
			const state = load(ctx.cwd);
			state.globs = [...new Set([...state.globs, ...globs])];
			writeJSON(statePath(ctx.cwd, "freeze.json"), state);
			ctx.ui.notify(`frozen: ${state.globs.join(", ")}`, "warn");
		},
	});

	pi.registerCommand("unfreeze", {
		description: "Unlock path glob(s): /unfreeze <glob> | all",
		handler: async (args, ctx) => {
			const arg = (args ?? "").trim();
			if (arg === "all" || arg === "") {
				writeJSON(statePath(ctx.cwd, "freeze.json"), { globs: [] });
				ctx.ui.notify("unfroze all", "info");
				return;
			}
			const state = load(ctx.cwd);
			const drop = new Set(arg.split(/\s+/));
			state.globs = state.globs.filter((g) => !drop.has(g));
			writeJSON(statePath(ctx.cwd, "freeze.json"), state);
			ctx.ui.notify(`frozen: ${state.globs.join(", ") || "(none)"}`, "info");
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		const globs = load(ctx.cwd).globs;
		if (globs.length === 0) return;

		if (event.toolName === "write" || event.toolName === "edit") {
			const paths = pathsFromToolInput(
				event.toolName,
				event.input as Record<string, unknown>,
			);
			for (const p of paths) {
				const g = matchesAny(p, globs);
				if (g) {
					return {
						block: true,
						reason: `"${p}" is frozen (matches "${g}"). Run /unfreeze ${g} to edit it.`,
					};
				}
			}
		}

		// bash branch (best-effort): catch frozen-path writes performed via the
		// shell (redirection, tee, sed -i, cp/mv dest) rather than write/edit.
		if (event.toolName === "bash") {
			const cmd = String(
				(event.input as Record<string, unknown>).command ?? "",
			);
			for (const p of bashWriteTargets(cmd)) {
				const g = matchesAny(p, globs);
				if (g) {
					return {
						block: true,
						reason: `"${p}" is frozen (matches "${g}"). Run /unfreeze ${g} to edit it.`,
					};
				}
			}
		}
	});
}
