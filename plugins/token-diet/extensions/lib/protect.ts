// protect.ts — quality-preserving text-compression primitives for token-diet's
// context-transform extensions. PURE (no OMP imports) so it is unit-testable
// (`bun plugins/token-diet/scripts/extensions.test.ts`) and reusable.
//
// The core idea — the improvement over caveman-code's LLMLingua/Provence
// integration, which compresses every token uniformly with (in its own words)
// "no force-preserve logic for code syntax, technical terms, or semantic
// anchors" — is a PROTECT MASK: high-value spans (fenced/inline code, paths,
// URLs, hashes, numbers, qualified identifiers, CONSTANTS, CLI flags) are lifted
// out into sentinel placeholders BEFORE any prose compression and restored
// byte-identical AFTER. Only the prose *between* protected spans is ever
// shortened. That same span set is exactly what you would hand a real
// LLMLingua-2 pass as `force_tokens` (with `force_reserve_digit` +
// `drop_consecutive`); see research/caveman-code.md §"improving preservation".
//
// Bias: when a pattern is unsure, it PROTECTS (compresses less) rather than
// risk dropping a detail. Over-protection costs a little ratio; under-protection
// costs correctness. We choose correctness.

import { createHash } from "node:crypto";

export type Level = "safe" | "lite" | "full";

export function sha1(s: string): string {
	return createHash("sha1").update(s).digest("hex");
}

// ~4 chars/token, matching OMP's and caveman-code's own rough estimate.
export function estimateTokens(s: string): number {
	return s ? Math.ceil(s.length / 4) : 0;
}

// Sentinels built at runtime (no control chars in source). A protected span
// becomes NUL<index>NUL; NUL never occurs in real model context, so prose
// rewriting can neither split nor match inside a placeholder.
const NUL = String.fromCharCode(0);
const ESC = String.fromCharCode(27);
const PH = new RegExp(`${NUL}(\\d+)${NUL}`, "g");
const ANSI = new RegExp(`${ESC}\\[[0-9;]*m`, "g");

// Ordered: earlier patterns win (fenced code before inline code before paths…).
// Each is applied only to the prose *gaps* between existing placeholders, so a
// later pattern can never corrupt an earlier span (e.g. the number rule cannot
// eat the digits of a placeholder).
const PROTECT: RegExp[] = [
	/```[\s\S]*?```/g, // fenced code (backtick)
	/~~~[\s\S]*?~~~/g, // fenced code (tilde)
	/`[^`\n]+`/g, // inline code
	/\b[a-z][a-z0-9+.-]*:\/\/[^\s)<>"']+/gi, // URLs / URIs (http, ssh, file, ado…)
	/\b[0-9a-f]{7,64}\b/gi, // hex / sha / object ids
	/(?:[A-Za-z]:\\|\.{0,2}\/)?(?:[\w.@~-]+[\\/])+[\w.@~+-]+/g, // paths (have a separator)
	/\b[\w.-]+\.(?:ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|cs|csx|rb|php|c|h|cpp|hpp|sh|ps1|yml|yaml|toml|json|xml|sql|md|txt|cfg|ini|env|lock|csproj|sln)\b/gi, // bare filename.ext
	/(?<![\w-])--?[A-Za-z][\w-]*(?:=\S+)?/g, // CLI flags (--flag, -x, --k=v)
	/\b[A-Z][A-Z0-9]{2,}(?:_[A-Z0-9]+)+\b/g, // UPPER_SNAKE_CASE constants
	/\b\w+(?:[._:#$/-]\w+)+\b/g, // dotted/qualified ids: a.b.c, ns::x, kebab-case
	/[+-]?\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?%?\b/g, // numbers (force_reserve_digit)
];

// Apply `fn` only to substrings that lie OUTSIDE existing placeholders.
function mapGaps(s: string, fn: (gap: string) => string): string {
	let out = "";
	let last = 0;
	PH.lastIndex = 0;
	let m: RegExpExecArray | null;
	// biome-ignore lint/suspicious/noAssignInExpressions: standard exec loop
	while ((m = PH.exec(s)) !== null) {
		out += fn(s.slice(last, m.index)) + m[0];
		last = m.index + m[0].length;
	}
	return out + fn(s.slice(last));
}

/** Replace every high-value span with a placeholder; return spans to restore. */
export function protect(text: string): { masked: string; spans: string[] } {
	// If the raw sentinel char already occurs in the input, masking is unsafe:
	// a pre-existing NUL<digits>NUL would be misread by restore() as one of our
	// placeholders and silently dropped. Bail out — the lossless guarantee beats
	// compressing that (vanishingly rare) input.
	if (text.includes(NUL)) return { masked: text, spans: [] };
	const spans: string[] = [];
	let work = text;
	for (const re of PROTECT) {
		work = mapGaps(work, (gap) =>
			gap.replace(re, (hit) => `${NUL}${spans.push(hit) - 1}${NUL}`),
		);
	}
	return { masked: work, spans };
}

/** Inverse of protect(): splice the original spans back in, byte-identical. */
export function restore(masked: string, spans: string[]): string {
	// An out-of-range index means the matched text was NOT one of our
	// placeholders (a pre-existing NUL<digits>NUL in the original) — return it
	// verbatim rather than converting it to a deletion.
	return masked.replace(PH, (full, d: string) => spans[Number(d)] ?? full);
}

const FILLER_LITE = [
	"please",
	"kindly",
	"just",
	"really",
	"very",
	"basically",
	"actually",
	"simply",
	"essentially",
	"literally",
	"obviously",
	"clearly",
	"of course",
	"as you can see",
	"it is worth noting that",
	"it should be noted that",
	"please note that",
	"note that",
];

function escapeRe(s: string): string {
	return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function dropFiller(s: string, list: string[]): string {
	for (const w of list) {
		s = s.replace(new RegExp(`\\b${escapeRe(w)}\\b[ \t]?`, "gi"), "");
	}
	return s;
}

/**
 * Shorten prose only (placeholders are inert). Levels mirror the caveman skill:
 *  - safe: genuinely near-lossless — strip ANSI, trailing spaces, collapse
 *          blank-line runs. Interior column spacing is PRESERVED (tables, diffs,
 *          ASCII art keep their alignment); no word drop.
 *  - lite: + collapse interior multi-space runs + drop curated filler words.
 *  - full: + drop articles (a/an/the).
 */
export function compressProse(masked: string, level: Level): string {
	let s = masked;
	s = s.replace(ANSI, "");
	s = s.replace(/[ \t]+$/gm, "");
	s = s.replace(/\n{3,}/g, "\n\n");
	// `safe` must keep interior single-space-significant runs intact (column
	// alignment), so the mid-line space collapse is reserved for lite/full.
	if (level === "safe") return s;
	s = s.replace(/(\S) {2,}(\S)/g, "$1 $2"); // keep leading indentation
	s = dropFiller(s, FILLER_LITE);
	if (level === "lite") return s.replace(/ {2,}/g, " ");
	s = s.replace(/\b(?:a|an|the)\b[ \t]/gi, "");
	return s.replace(/ {2,}/g, " ");
}

export interface CompressOpts {
	level: Level;
	/** Skip blocks below this length (activationThreshold). 0 = always. */
	minChars?: number;
}

/**
 * protect → compressProse → restore, with two safety disciplines borrowed from
 * caveman-code: an activation threshold (leave small blocks alone) and a
 * never-expand guarantee (return the original if compression didn't help or
 * threw). Protected detail is always byte-identical to the input.
 */
export function compress(text: string, opts: CompressOpts): string {
	if (typeof text !== "string") return text;
	if ((opts.minChars ?? 0) > 0 && text.length < (opts.minChars as number)) {
		return text;
	}
	let out: string;
	try {
		const { masked, spans } = protect(text);
		out = restore(compressProse(masked, opts.level), spans);
	} catch {
		return text;
	}
	return out.length > 0 && out.length < text.length ? out : text;
}

// Harmless default export in case extension discovery scans lib/ as an entry.
export default function () {}
