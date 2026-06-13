// model-routing.ts — dispatch tier logger + routing diagnostic.
//
// In OMP the actual tier -> model mapping is native (.omp/config.yml modelRoles
// + each agent's `model:` frontmatter). This extension adds an observability
// layer the config alone doesn't give you: it records every subagent dispatch
// with its resolved tier to .omp/state/model-routing.log, and registers a
// `/routing` command that prints the tier table.
//
// All tiers are cloud. The small tier (`pi/smol`) is a CHEAP-cloud, high-volume
// tier (default modelRoles.smol = claude-haiku-4-5; cheaper still via the
// copilot-preset plugin). Source of truth:
// skills/dev-team-knowledge/model-routing.json.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	agentModel,
	appendJSONL,
	loadRouting,
	nowISO,
	statePath,
} from "./lib/shared.ts";

const SMALL_TIER_MODELS = new Set(["pi/smol", "smol"]);

function tierOf(model: string | null): string {
	if (model === null) return "default";
	if (SMALL_TIER_MODELS.has(model)) return "small";
	if (model.includes("opus")) return "deep";
	if (model.includes("sonnet")) return "balanced";
	return "pinned";
}

export default function modelRouting(pi: ExtensionAPI) {
	pi.setLabel("model-routing");

	// Log each subagent dispatch with its resolved tier (observability only —
	// never blocks).
	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "task") return;
		const agent = String((event.input as Record<string, unknown>).agent ?? "");
		if (!agent) return;
		const model = agentModel(agent);
		appendJSONL(statePath(ctx.cwd, "model-routing.log"), {
			ts: nowISO(),
			agent,
			model,
			tier: tierOf(model),
		});
	});

	// Diagnostic: print the tier -> frontmatter map (complements the
	// /model-routing-check skill, which also resolves against your config).
	pi.registerCommand("routing", {
		description: "Show the dev-team tier -> model map",
		handler: async (_args, ctx) => {
			const routing = loadRouting();
			if (!routing) {
				ctx.ui.notify(
					"no model-routing.json found in skills/dev-team-knowledge",
					"error",
				);
				return;
			}
			const lines = Object.entries(routing.tiers).map(
				([tier, t]) => `${tier}: ${t.frontmatter} (${t.intent})`,
			);
			ctx.ui.notify(lines.join("\n"), "info");
		},
	});
}
