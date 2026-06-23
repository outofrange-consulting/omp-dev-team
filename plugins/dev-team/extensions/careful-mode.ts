// careful-mode.ts — /careful on|off|status toggle.
// Backing state read by destructive-guard.ts. Port of the Claude Code
// `/careful` skill + `careful-state.json`.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { readState, writeState } from "./lib/shared.ts";

interface CarefulState {
	active: boolean;
	since?: string;
}

export function isCareful(cwd: string): boolean {
	return readState<CarefulState>(cwd, "careful.json", {
		active: false,
	}).active;
}

export default function carefulMode(pi: ExtensionAPI) {
	pi.setLabel("careful-mode");

	pi.registerCommand("careful", {
		description: "Toggle careful mode (on|off|status): block destructive commands",
		handler: async (args, ctx) => {
			const arg = (args ?? "").trim().toLowerCase();
			if (arg === "on") {
				writeState(ctx.cwd, "careful.json", { active: true, since: new Date().toISOString() });
				ctx.ui.notify("careful mode ON — destructive commands will be blocked", "warn");
			} else if (arg === "off") {
				writeState(ctx.cwd, "careful.json", { active: false });
				ctx.ui.notify("careful mode OFF", "info");
			} else {
				ctx.ui.notify(`careful mode: ${isCareful(ctx.cwd) ? "ON" : "OFF"}`, "info");
			}
		},
	});
}
