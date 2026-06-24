// model-routing.ts — effort-band dispatch routing + observability + diagnostic.
//
// Base model resolution in OMP is native (.omp/config.yml modelRoles + each
// agent's `model:` frontmatter). This extension adds **effort-band routing** on
// top: the model is derived from the TASK SIZE (trivial/standard/complex, from
// the task-size-classifier, recorded by /scope in plan-gate state), not only
// from the agent's static tier. The agent's declared tier is the BASE band; the
// task size shifts it along the ladder [small, balanced, deep]. This is more
// deterministic than one-model-per-agent and ties spend to the work.
//
// It also logs every dispatch (observability) and registers /routing.
//
// Enforcement (config `effortBand.enforcement`, overridable by env
// DEV_TEAM_EFFORT_ROUTING):
//   off       — no band; pure static tiers (just log).
//   advisory  — (default) log + warn when the dispatched tier != the band tier.
//   enforce   — block the dispatch and tell the caller the model to use.
//
// copilot-preset is unaffected: the band picks a TIER, then modelRoles resolves
// the concrete model (Anthropic id or github-copilot/*).

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	type EffortBandConfig,
	agentModel,
	appendJSONL,
	effectiveBand,
	loadRouting,
	nowISO,
	readState,
	statePath,
} from "./lib/shared.ts";

const SMALL_TIER_MODELS = new Set(["pi/smol", "smol"]);

function tierOf(model: string | null): string {
	if (model === null || model === "") return "default";
	if (SMALL_TIER_MODELS.has(model)) return "small";
	if (model.includes("opus")) return "deep";
	if (model.includes("sonnet")) return "balanced";
	if (model === "small" || model === "balanced" || model === "deep") return model;
	return "pinned";
}

function taskSize(cwd: string): string {
	const st = readState<{ size?: string }>(cwd, "plan-gate.json", {});
	return st.size ?? "standard";
}

export default function modelRouting(pi: ExtensionAPI) {
	pi.setLabel("model-routing");

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "task") return;
		const input = event.input as Record<string, unknown>;
		const agent = String(input.agent ?? "");
		if (!agent) return;

		const routing = loadRouting();
		const band: EffortBandConfig | undefined = routing?.effortBand;
		const mode = (process.env.DEV_TEAM_EFFORT_ROUTING ?? band?.enforcement ?? "advisory").toLowerCase();

		const floor = tierOf(agentModel(agent)); // the agent's declared tier = floor
		const size = taskSize(ctx.cwd);
		const dispatched = tierOf(input.model == null ? null : String(input.model)) === "default"
			? floor // no explicit model -> the agent's floor tier is used
			: tierOf(String(input.model));
		const eff = mode === "off" ? floor : effectiveBand(floor, size, band);

		appendJSONL(statePath(ctx.cwd, "model-routing.log"), {
			ts: nowISO(),
			agent,
			floor,
			size,
			effective: eff,
			dispatched,
			mode,
		});

		if (mode === "off" || eff === dispatched || floor === "default" || floor === "pinned") {
			return;
		}

		const wantModel = routing?.tiers?.[eff]?.frontmatter ?? eff;
		const msg =
			`effort-band: ${agent} floor=${floor}, task size=${size} -> dispatch at "${eff}" ` +
			`(model: ${wantModel}), but got "${dispatched}".`;
		if (mode === "enforce") {
			return {
				block: true,
				reason: `${msg}\nRe-dispatch with model: ${wantModel}. (Set DEV_TEAM_EFFORT_ROUTING=advisory to warn instead, or =off to disable.)`,
			};
		}
		ctx.ui.notify(msg, "warn"); // advisory
	});

	pi.registerCommand("routing", {
		description: "Show the dev-team tier map + effort-band (current task size and effective bands)",
		handler: async (_args, ctx) => {
			const routing = loadRouting();
			if (!routing) {
				ctx.ui.notify("no model-routing.json found in skills/dev-team-knowledge", "error");
				return;
			}
			const lines = Object.entries(routing.tiers).map(
				([tier, t]) => `${tier}: ${t.frontmatter} (${t.intent})`,
			);
			const band = routing.effortBand;
			if (band) {
				const size = taskSize(ctx.cwd);
				const mode = (process.env.DEV_TEAM_EFFORT_ROUTING ?? band.enforcement ?? "advisory").toLowerCase();
				lines.push("", `effort-band [${mode}] — current task size: ${size}`);
				for (const b of band.ladder) {
					lines.push(`  floor ${b} -> ${effectiveBand(b, size, band)}`);
				}
			}
			ctx.ui.notify(lines.join("\n"), "info");
		},
	});
}
