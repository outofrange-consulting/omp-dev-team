// cache-meter.ts — live prompt-cache / cost sensor for token-diet.
//
// Current OMP reports per-turn billing on every assistant message
// (`message.usage`: input/output/cacheRead/cacheWrite/cost/reasoningTokens), and
// surfaces provider rate-limit headers on `after_provider_response`. This
// extension accumulates that into a session cache-health summary and exposes
// `/cache-health`, so the central token-diet question — *is our context
// compression busting the provider prompt-cache prefix?* — is answered with
// measured numbers instead of assumptions.
//
// Read-only: it never mutates messages or requests. Disable with
// TOKEN_DIET_CACHE_METER=off. Off changes nothing else in token-diet.

import { appendFileSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { parseLevel } from "./context-compress.ts";
import {
	type CacheAccum,
	addUsage,
	cacheChurn,
	cacheReadRate,
	emptyAccum,
	extractUsage,
	formatReport,
	reasoningShare,
} from "./lib/cache-stats.ts";

function logPath(): string {
	const override = process.env.TOKEN_DIET_CACHE_LOG?.trim();
	if (override) return override;
	const base = process.env.OMP_HOME?.trim() || join(homedir(), ".omp");
	return join(base, "state", "token-diet", "cache-meter.jsonl");
}

function appendJSONL(line: Record<string, unknown>): void {
	try {
		const p = logPath();
		mkdirSync(dirname(p), { recursive: true });
		appendFileSync(p, `${JSON.stringify(line)}\n`);
	} catch {
		// best-effort metrics; never disturb the session
	}
}

// `lite`/`full` rewrite prose in old messages (prefix-mutating); `safe` only
// strips ANSI/whitespace and `off` is disabled. Only the prefix-mutating levels
// pose a real cache-prefix risk, so that is what we flag against.
function compressionMutatesPrefix(): boolean {
	const lvl = parseLevel(process.env.TOKEN_DIET_CONTEXT_COMPRESS);
	return lvl === "lite" || lvl === "full";
}

// Keep only the provider quota/rate-limit headers, normalized to short lines.
function quotaFromHeaders(headers: unknown): string[] {
	if (!headers || typeof headers !== "object") return [];
	const out: string[] = [];
	for (const [k, v] of Object.entries(headers as Record<string, unknown>)) {
		const key = k.toLowerCase();
		if (key.includes("ratelimit") && (key.includes("remaining") || key.includes("reset"))) {
			out.push(`${key.replace(/^anthropic-/, "")}=${String(v)}`);
		}
	}
	return out;
}

export default function cacheMeter(pi: ExtensionAPI) {
	pi.setLabel("cache-meter");
	const off = ["off", "0", "none", "false"].includes(
		(process.env.TOKEN_DIET_CACHE_METER ?? "").trim().toLowerCase(),
	);
	if (off) return;

	let acc: CacheAccum = emptyAccum();
	let quota: string[] = [];

	pi.on("session_start", async () => {
		acc = emptyAccum();
		quota = [];
	});

	// One assistant message per turn carries the billed usage.
	pi.on("turn_end", async (event) => {
		try {
			const u = extractUsage((event as { message?: unknown }).message);
			if (u) addUsage(acc, u);
		} catch {
			/* never disturb the turn */
		}
	});

	// Latest provider rate-limit headers (Anthropic ratelimit-*), best-effort.
	pi.on("after_provider_response", async (event) => {
		try {
			const q = quotaFromHeaders((event as { headers?: unknown }).headers);
			if (q.length > 0) quota = q;
		} catch {
			/* ignore */
		}
	});

	pi.registerCommand("cache-health", {
		description:
			"Show this session's prompt-cache read/churn, cost, thinking share, and quota",
		handler: async (_args, ctx) => {
			let contextPct: number | null = null;
			try {
				const usage = ctx.getContextUsage?.();
				if (usage && typeof usage === "object" && "percent" in usage) {
					contextPct = Number((usage as { percent: number }).percent);
				}
			} catch {
				/* ignore */
			}
			const report = formatReport(acc, {
				compressionActive: compressionMutatesPrefix(),
				contextPct,
				quota,
			});
			appendJSONL({
				ts: new Date().toISOString(),
				turns: acc.billedTurns,
				cost: acc.cost,
				input: acc.input,
				output: acc.output,
				cacheRead: acc.cacheRead,
				cacheWrite: acc.cacheWrite,
				cacheReadRate: cacheReadRate(acc),
				cacheChurn: cacheChurn(acc),
				reasoningShare: reasoningShare(acc),
				compressionActive: compressionMutatesPrefix(),
				contextPct,
			});
			ctx.ui.notify(report.text, report.level);
		},
	});
}
