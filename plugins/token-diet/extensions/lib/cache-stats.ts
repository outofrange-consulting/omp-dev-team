// cache-stats.ts — PURE accounting for the prompt-cache / cost meter. No OMP or
// fs dependency; unit-tested in scripts/extensions.test.ts.
//
// Why this exists: token-diet's context transforms (context-compress, the two
// dedups) rewrite OLD assistant/tool messages — exactly the stable PREFIX a
// provider KV-caches. If a transform changes a byte before the provider's cache
// breakpoint, the prefix is invalidated and that turn is billed as cacheWrite
// (1.25x input) instead of cacheRead (0.1x input). This module turns the
// per-turn `usage` OMP now reports (input/output/cacheRead/cacheWrite/cost) into
// a glanceable cache-health signal so that risk is MEASURED, not assumed.

// The fields we read off an assistant message's `usage` (pi-catalog `Usage`).
// Everything is optional/defensive: an unexpected shape yields nulls, never throws.
export interface TurnUsage {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	reasoningTokens: number;
	costTotal: number;
}

export interface CacheAccum {
	turns: number;
	billedTurns: number; // turns that actually carried usage numbers
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	reasoning: number;
	cost: number;
}

export function emptyAccum(): CacheAccum {
	return {
		turns: 0,
		billedTurns: 0,
		input: 0,
		output: 0,
		cacheRead: 0,
		cacheWrite: 0,
		reasoning: 0,
		cost: 0,
	};
}

function num(v: unknown): number {
	return typeof v === "number" && Number.isFinite(v) ? v : 0;
}

/**
 * Defensively pull the `usage` block off an assistant message (turn_end.message
 * / message_end.message). Returns null when there is no numeric usage to read,
 * so the caller can distinguish a billed turn from a non-assistant turn.
 */
export function extractUsage(message: unknown): TurnUsage | null {
	if (!message || typeof message !== "object") return null;
	const u = (message as { usage?: unknown }).usage;
	if (!u || typeof u !== "object") return null;
	const o = u as Record<string, unknown>;
	// Require at least one of the token buckets to be a number; otherwise this
	// isn't a usage-bearing message.
	const keys = ["input", "output", "cacheRead", "cacheWrite"] as const;
	if (!keys.some((k) => typeof o[k] === "number")) return null;
	const cost = o.cost && typeof o.cost === "object"
		? num((o.cost as Record<string, unknown>).total)
		: 0;
	return {
		input: num(o.input),
		output: num(o.output),
		cacheRead: num(o.cacheRead),
		cacheWrite: num(o.cacheWrite),
		reasoningTokens: num(o.reasoningTokens),
		costTotal: cost,
	};
}

export function addUsage(acc: CacheAccum, u: TurnUsage): void {
	acc.turns += 1;
	acc.billedTurns += 1;
	acc.input += u.input;
	acc.output += u.output;
	acc.cacheRead += u.cacheRead;
	acc.cacheWrite += u.cacheWrite;
	acc.reasoning += u.reasoningTokens;
	acc.cost += u.costTotal;
}

/** Total prompt tokens seen = fresh input + cache reads + cache writes. */
export function promptTokens(acc: CacheAccum): number {
	return acc.input + acc.cacheRead + acc.cacheWrite;
}

/**
 * Fraction of all prompt tokens served from cache (the headline efficiency
 * number). 0 when nothing has been billed yet. Higher is cheaper.
 */
export function cacheReadRate(acc: CacheAccum): number {
	const p = promptTokens(acc);
	return p > 0 ? acc.cacheRead / p : 0;
}

/**
 * Of the cacheable region (reads + writes), the share that had to be (re)written
 * this session. HIGH churn is the prefix-instability smell: if a compressor is
 * mutating the cached prefix, cacheWrite stays high and this ratio rises. 0 when
 * the cache was never exercised.
 */
export function cacheChurn(acc: CacheAccum): number {
	const cached = acc.cacheRead + acc.cacheWrite;
	return cached > 0 ? acc.cacheWrite / cached : 0;
}

/** Share of output tokens that were thinking/reasoning tokens (Opus 4.8 bloat). */
export function reasoningShare(acc: CacheAccum): number {
	return acc.output > 0 ? acc.reasoning / acc.output : 0;
}

function pct(x: number): string {
	return `${Math.round(x * 100)}%`;
}

export interface ReportOpts {
	/** Is a prefix-mutating transform (context-compress at lite/full) active? */
	compressionActive?: boolean;
	/** Context-window usage %, if available from getContextUsage(). */
	contextPct?: number | null;
	/** Latest provider rate-limit / quota lines, if captured. */
	quota?: string[];
	/** Churn at/above which we warn when compression is active. Default 0.5. */
	churnWarnAt?: number;
}

export interface Report {
	text: string;
	level: "info" | "warn";
}

/**
 * Render a one-glance cache/cost report and decide whether to flag a cache-bust
 * risk. The warning fires only when a prefix-mutating transform is active AND
 * churn is high AND the cache was actually exercised — i.e. real evidence the
 * compression may be paying off in visible tokens while quietly busting the
 * cheaper-by-10x cache read.
 */
export function formatReport(acc: CacheAccum, opts: ReportOpts = {}): Report {
	const churnWarnAt = opts.churnWarnAt ?? 0.5;
	if (acc.billedTurns === 0) {
		return {
			text: "cache-health: no billed turns yet (no usage recorded this session).",
			level: "info",
		};
	}
	const churn = cacheChurn(acc);
	const cached = acc.cacheRead + acc.cacheWrite;
	const risk = !!opts.compressionActive && cached > 0 && churn >= churnWarnAt;

	const parts: string[] = [];
	parts.push(`turns=${acc.billedTurns}`);
	parts.push(`$=${acc.cost.toFixed(4)}`);
	parts.push(
		`in=${acc.input} out=${acc.output} cacheR=${acc.cacheRead} cacheW=${acc.cacheWrite}`,
	);
	parts.push(`cache-read=${pct(cacheReadRate(acc))}`);
	parts.push(`cache-churn=${pct(churn)}`);
	if (acc.reasoning > 0) parts.push(`think=${pct(reasoningShare(acc))} of out`);
	if (typeof opts.contextPct === "number") {
		parts.push(`ctx=${Math.round(opts.contextPct)}%`);
	}
	let text = `cache-health: ${parts.join(" | ")}`;
	if (opts.quota && opts.quota.length > 0) {
		text += `\n  quota: ${opts.quota.join(" ")}`;
	}
	if (risk) {
		text +=
			`\n  ⚠ prefix-mutating compression is ON and cache-churn is ${pct(churn)} — ` +
			`the compressor may be invalidating the prompt-cache prefix (cacheWrite is ` +
			`1.25x input, cacheRead only 0.1x). Compare a stretch with ` +
			`TOKEN_DIET_CONTEXT_COMPRESS=off; if churn drops, freeze the cached prefix.`;
	}
	return { text, level: risk ? "warn" : "info" };
}

/**
 * Compact one-line summary for the footer/status bar (ExtensionUIContext
 * setStatus). Empty string before any billed turn (so nothing is shown yet).
 * Mirrors formatReport's warning condition with a trailing ⚠ marker.
 */
export function formatStatusLine(
	acc: CacheAccum,
	opts: { compressionActive?: boolean; churnWarnAt?: number } = {},
): string {
	if (acc.billedTurns === 0) return "";
	const churn = cacheChurn(acc);
	const cached = acc.cacheRead + acc.cacheWrite;
	const risk = !!opts.compressionActive && cached > 0 && churn >= (opts.churnWarnAt ?? 0.5);
	const bits = [
		`$${acc.cost.toFixed(2)}`,
		`cache ${pct(cacheReadRate(acc))}`,
		`churn ${pct(churn)}`,
	];
	if (acc.reasoning > 0) bits.push(`think ${pct(reasoningShare(acc))}`);
	return `td ${bits.join(" ")}${risk ? " ⚠" : ""}`;
}

// Harmless default export in case extension discovery scans lib/ as an entry.
export default function () {}
