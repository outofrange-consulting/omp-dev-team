// model-routing.ts — local-model availability gate + dispatch logger.
//
// Faithful port of the Claude Code `agent-model-resolve.sh` hook. In OMP the
// actual tier -> model mapping is native (.omp/config.yml modelRoles + each
// agent's `model:` frontmatter). This extension adds the two behaviours the
// shell hook gave you that config alone cannot:
//   1. A pre-dispatch GATE: when a small-tier agent (model: pi/smol, i.e. the
//      LOCAL model) is spawned but the local backend is unreachable, the `task`
//      call is BLOCKED with an actionable message instead of failing mid-run.
//   2. A dispatch LOG (the "bump log" analog) at .omp/state/model-routing.log.
//
// See .omp/knowledge/model-routing.json for the source of truth and
// /model-routing-check (skill) / the `routing` command for diagnostics.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	agentModel,
	appendJSONL,
	loadRouting,
	nowISO,
	probeLocal,
	statePath,
} from "./lib/shared.ts";

const LOCAL_TIER_MODELS = new Set(["pi/smol", "smol"]);

export default function modelRouting(pi: ExtensionAPI) {
	pi.setLabel("model-routing");

	// Cache the probe result per session so we don't hit the backend on every
	// dispatch. Re-probed on session_start.
	let localUp: boolean | null = null;
	let probedBackend = "";
	let probedUrl = "";

	async function refreshProbe(cwd: string): Promise<void> {
		const routing = loadRouting(cwd);
		if (!routing) {
			localUp = null;
			return;
		}
		probedBackend = routing.local.backend;
		probedUrl = routing.local.probe[probedBackend] ?? "";
		localUp = probedUrl ? await probeLocal(probedUrl) : null;
	}

	pi.on("session_start", async (_event, ctx) => {
		await refreshProbe(ctx.cwd);
		const routing = loadRouting(ctx.cwd);
		if (!routing) return;
		if (localUp === false) {
			ctx.ui.notify(
				`local model backend (${probedBackend}) unreachable at ${probedUrl} — ` +
					`small-tier agents will be blocked. Start it, or set modelRoles.smol ` +
					`to ${routing.local.fallback} in .omp/config.yml.`,
				"warn",
			);
		} else if (localUp === true) {
			ctx.ui.notify(
				`local model ready: ${routing.local.model} (${probedBackend})`,
				"info",
			);
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "task") return;
		const agent = String(
			(event.input as Record<string, unknown>).agent ?? "",
		);
		if (!agent) return;

		const model = agentModel(ctx.cwd, agent);
		const isLocalTier = model !== null && LOCAL_TIER_MODELS.has(model);

		appendJSONL(statePath(ctx.cwd, "model-routing.log"), {
			ts: nowISO(),
			agent,
			model,
			tier: isLocalTier ? "local" : "cloud",
			localUp,
		});

		if (!isLocalTier) return;

		// Small-tier agent -> needs the local backend. Probe lazily if unknown.
		if (localUp === null) await refreshProbe(ctx.cwd);
		if (localUp === false) {
			const routing = loadRouting(ctx.cwd);
			const fb = routing?.local.fallback ?? "claude-haiku-4-5";
			return {
				block: true,
				reason:
					`Agent "${agent}" is small-tier (model: ${model}) and requires the ` +
					`local backend (${probedBackend}) at ${probedUrl}, which is unreachable.\n` +
					`Fix one of:\n` +
					`  • Start the backend (e.g. \`ollama serve\` + \`ollama pull qwen2.5-coder:14b\`).\n` +
					`  • Set modelRoles.smol: ${fb} in .omp/config.yml to run this tier on cloud.\n` +
					`Run /skill:model-routing-check for the full effective map.`,
			};
		}
	});

	// Lightweight diagnostic command (complements the skill).
	pi.registerCommand("routing", {
		description: "Show effective tier->model routing and local backend status",
		handler: async (_args, ctx) => {
			const routing = loadRouting(ctx.cwd);
			if (!routing) {
				ctx.ui.notify("no .omp/knowledge/model-routing.json found", "error");
				return;
			}
			await refreshProbe(ctx.cwd);
			const status = localUp === true ? "UP" : localUp === false ? "DOWN" : "n/a";
			ctx.ui.notify(
				`small=${routing.local.model} [${probedBackend}:${status}]  ` +
					`fallback=${routing.local.fallback}`,
				localUp === false ? "warn" : "info",
			);
		},
	});
}
