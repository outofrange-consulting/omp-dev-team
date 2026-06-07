// telemetry.ts — lightweight per-session friction meter. Port of the Claude
// Code `telemetry.sh` / `cost-meter.sh` hooks. Counts turns and tool calls,
// records context usage, and exposes /cost-report.
//
// North-star alignment: we measure friction (turns, tool churn, context
// pressure) so observed friction can become a concrete improvement.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { appendJSONL, nowISO, statePath } from "./lib/shared.ts";

interface Counters {
	turns: number;
	toolCalls: Record<string, number>;
	blocked: number;
}

export default function telemetry(pi: ExtensionAPI) {
	pi.setLabel("telemetry");

	let c: Counters = { turns: 0, toolCalls: {}, blocked: 0 };

	pi.on("session_start", async () => {
		c = { turns: 0, toolCalls: {}, blocked: 0 };
	});

	pi.on("turn_end", async () => {
		c.turns += 1;
	});

	pi.on("tool_result", async (event) => {
		c.toolCalls[event.toolName] = (c.toolCalls[event.toolName] ?? 0) + 1;
		if (event.isError) c.blocked += 1;
	});

	pi.registerCommand("cost-report", {
		description: "Print this session's turn/tool/context friction summary",
		handler: async (_args, ctx) => {
			let ctxPct = "n/a";
			try {
				const usage = ctx.getContextUsage?.();
				if (usage && typeof usage === "object" && "percentage" in usage) {
					ctxPct = `${Math.round(Number((usage as { percentage: number }).percentage))}%`;
				}
			} catch {
				/* ignore */
			}
			const tools = Object.entries(c.toolCalls)
				.sort((a, b) => b[1] - a[1])
				.map(([k, v]) => `${k}:${v}`)
				.join(" ");
			appendJSONL(statePath(ctx.cwd, "telemetry.jsonl"), {
				ts: nowISO(),
				...c,
				contextUsed: ctxPct,
			});
			ctx.ui.notify(
				`turns=${c.turns} ctx=${ctxPct} errors=${c.blocked} | ${tools || "no tool calls"}`,
				"info",
			);
		},
	});
}
