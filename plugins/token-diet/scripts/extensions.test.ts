// Unit tests for token-diet's pure context-transform logic.
//   bun plugins/token-diet/scripts/extensions.test.ts
// No OMP dependency — exercises the quality-critical invariants directly:
// protect/restore is lossless, compression preserves every technical detail,
// the activation threshold + never-expand guards hold, and the message-array
// transforms (lossless dedup, lossy recency-preserving compress) behave.

import {
	type Level,
	compress,
	compressProse,
	protect,
	restore,
} from "../extensions/lib/protect.ts";
import {
	collapseDuplicateBlobs,
	compressOldMessages,
	textBlobs,
} from "../extensions/lib/messages.ts";
import { parseLevel } from "../extensions/context-compress.ts";
import {
	addUsage,
	cacheChurn,
	cacheReadRate,
	emptyAccum,
	extractUsage,
	formatReport,
	formatStatusLine,
	reasoningShare,
} from "../extensions/lib/cache-stats.ts";

let failures = 0;
function check(name: string, cond: boolean, extra?: unknown): void {
	if (cond) {
		console.log(`  ok  ${name}`);
	} else {
		failures++;
		console.error(`FAIL  ${name}`, extra ?? "");
	}
}

// The "must never be altered" tokens — the whole point of the protect mask.
const PRESERVE = [
	"`src/app/main.ts`",
	"https://example.com/x?a=1",
	"a1b2c3d4e5f6",
	"42.5%",
	"MAX_RETRIES",
	"--no-config",
	"foo.bar.baz",
	"ns::Widget",
];
const PROSE = `The function in \`src/app/main.ts\` will, of course, just fetch
https://example.com/x?a=1 and then basically retry up to MAX_RETRIES times. See
commit a1b2c3d4e5f6. The success rate is really 42.5% and the flag --no-config
disables it. Please call foo.bar.baz() and ns::Widget as you can see.`;

// 1) protect → restore is byte-identical (lossless) on mixed content.
{
	const fenced = "```ts\nconst x = 1\n```";
	const sample = `${PROSE}\n\n${fenced}\n\nplain tail text here.`;
	const { masked, spans } = protect(sample);
	check("protect/restore round-trips exactly", restore(masked, spans) === sample);
	check("protect actually masked something", spans.length > 0, spans.length);
	check(
		"masked prose no longer contains the raw URL",
		!masked.includes("https://example.com/x?a=1"),
	);
}

// 2) compression preserves every technical detail, at every level.
for (const level of ["safe", "lite", "full"] as Level[]) {
	const out = compress(PROSE, { level });
	for (const tok of PRESERVE) {
		check(`[${level}] preserves ${tok}`, out.includes(tok), out);
	}
}

// 3) full compression shrinks prose; safe ≤ original.
{
	const full = compress(PROSE, { level: "full" });
	const safe = compress(PROSE, { level: "safe" });
	check("full compression shrinks prose", full.length < PROSE.length, {
		from: PROSE.length,
		to: full.length,
	});
	check("full drops the article 'The '", !/\bThe function\b/.test(full), full);
	check("full drops filler 'just '", !/\bjust fetch\b/.test(full), full);
	check("safe never grows", safe.length <= PROSE.length);
}

// 4) activation threshold: below minChars => returned unchanged.
{
	const small = "short note with the word just in it";
	check(
		"below activationThreshold is untouched",
		compress(small, { level: "full", minChars: 600 }) === small,
	);
}

// 5) never-expand: an all-protected block (no compressible prose) is unchanged.
{
	const codeOnly = "```js\n" + "const a = 1;\n".repeat(40) + "```";
	check("all-protected block returned as-is", compress(codeOnly, { level: "full" }) === codeOnly);
}

// 6) textBlobs handles string content, parts arrays, and junk shapes.
{
	const strMsg = { role: "tool", content: "hello" };
	const blobsStr = textBlobs(strMsg);
	blobsStr[0]?.set("HELLO");
	check("textBlobs read+write string content", strMsg.content === "HELLO");

	const partMsg = {
		role: "assistant",
		content: [{ type: "text", text: "a" }, { type: "image" }, { content: "b" }],
	};
	const blobsParts = textBlobs(partMsg);
	check("textBlobs finds .text and .content parts", blobsParts.length === 2, blobsParts.length);

	check("textBlobs tolerates junk", textBlobs(42).length === 0);
	check("textBlobs tolerates null", textBlobs(null).length === 0);
}

// 7) collapseDuplicateBlobs: lossless dedup, keep last, never touch user/system.
{
	const big = `BIGBLOCK ${"x".repeat(1500)}`;
	const messages: Array<{ role: string; content: string }> = [
		{ role: "tool", content: big },
		{ role: "assistant", content: "small reply" },
		{ role: "user", content: big }, // user copy must be untouched
		{ role: "tool", content: big }, // last assistant/tool copy kept verbatim
	];
	const saved = collapseDuplicateBlobs(messages, 1200);
	check("dedup saved tokens > 0", saved > 0, saved);
	check("dedup stubbed the first tool copy", messages[0].content.includes("context-dedup"));
	check("dedup left the user copy intact", messages[2].content === big);
	check("dedup kept the last tool copy verbatim", messages[3].content === big);
	check("dedup is a no-op on junk input", collapseDuplicateBlobs(null, 1200) === 0);
}

// 8) compressOldMessages: compress old prose, preserve recency + details.
{
	const oldMsg = { role: "assistant", content: PROSE + " ".repeat(0) + PROSE };
	const recentMsg = { role: "assistant", content: PROSE };
	const userMsg = { role: "user", content: PROSE };
	const messages = [userMsg, oldMsg, recentMsg];
	const before = oldMsg.content.length;
	const saved = compressOldMessages(messages, { level: "full", minChars: 200, keepRecent: 1 });
	check("compressOldMessages saved tokens > 0", saved > 0, saved);
	check("old message was shortened", oldMsg.content.length < before);
	check("old message kept a path detail", oldMsg.content.includes("src/app/main.ts"));
	check("recent message untouched (recency window)", recentMsg.content === PROSE);
	check("user message untouched", userMsg.content === PROSE);
}

// 8b) protect/restore is lossless even when the ORIGINAL text already contains a
// NUL<digits>NUL sequence that looks exactly like our runtime placeholder. The
// round-trip must NOT silently delete it (regression for the sentinel-collision
// data loss).
{
	const NUL = String.fromCharCode(0);
	const sample = `before ${NUL}999${NUL} after`;
	const { masked, spans } = protect(sample);
	check("protect bails out on pre-existing NUL sentinel", spans.length === 0, spans.length);
	check("restore round-trips a pre-existing NUL sentinel losslessly", restore(masked, spans) === sample);
	check("compress is a lossless no-op on a NUL-sentinel input", compress(sample, { level: "full" }) === sample);
}

// 8c) `safe`-level compression preserves multi-space column alignment (tables,
// diffs, ASCII art). Interior single-space-significant runs must survive safe.
{
	const table = "NAME    VALUE\nfoo     1\nbarbaz  22";
	const out = compress(table, { level: "safe" });
	check("safe preserves multi-space column alignment", out === table, out);
	// And the lossy levels are still allowed to collapse interior runs.
	const lite = compressProse(table, "lite");
	check("lite collapses interior multi-space runs", !lite.includes("NAME    VALUE"), lite);
}

// 9) context-compress level parsing: safe by default, off disables.
{
	check("parseLevel() unset => safe", parseLevel(undefined) === "safe");
	check("parseLevel('') => safe", parseLevel("") === "safe");
	check("parseLevel('SAFE') => safe", parseLevel("SAFE") === "safe");
	check("parseLevel('lite') => lite", parseLevel("lite") === "lite");
	check("parseLevel('full') => full", parseLevel("full") === "full");
	check("parseLevel('off') => null", parseLevel("off") === null);
	check("parseLevel('0') => null", parseLevel("0") === null);
	check("parseLevel('garbage') => safe", parseLevel("garbage") === "safe");
}

// 10) cache-stats: defensive usage extraction + cache-health math + warning.
{
	// extractUsage tolerates junk and non-usage messages.
	check("extractUsage(null) => null", extractUsage(null) === null);
	check("extractUsage(no usage) => null", extractUsage({ role: "assistant" }) === null);
	check(
		"extractUsage(empty usage) => null",
		extractUsage({ usage: { cost: {} } }) === null,
	);
	const u = extractUsage({
		role: "assistant",
		usage: {
			input: 100,
			output: 40,
			cacheRead: 900,
			cacheWrite: 0,
			reasoningTokens: 10,
			cost: { total: 0.0123 },
		},
	});
	check("extractUsage reads token buckets", !!u && u.cacheRead === 900 && u.input === 100, u);
	check("extractUsage reads cost.total", !!u && u.costTotal === 0.0123, u?.costTotal);
	check("extractUsage tolerates string junk fields", extractUsage({ usage: { input: "x" } }) === null);

	// Healthy cache: high read, low churn -> no warning even with compression on.
	const healthy = emptyAccum();
	addUsage(healthy, { input: 100, output: 40, cacheRead: 900, cacheWrite: 0, reasoningTokens: 10, costTotal: 0.01 });
	check("cacheReadRate healthy ~0.9", Math.abs(cacheReadRate(healthy) - 0.9) < 0.001, cacheReadRate(healthy));
	check("cacheChurn healthy = 0", cacheChurn(healthy) === 0, cacheChurn(healthy));
	check("reasoningShare healthy = 0.25", Math.abs(reasoningShare(healthy) - 0.25) < 0.001, reasoningShare(healthy));
	const okReport = formatReport(healthy, { compressionActive: true });
	check("healthy report is info (no false alarm)", okReport.level === "info", okReport.level);
	check("report includes cost", okReport.text.includes("$="), okReport.text);

	// Prefix-busting pattern: cache constantly rewritten, never read back.
	const busted = emptyAccum();
	addUsage(busted, { input: 100, output: 20, cacheRead: 50, cacheWrite: 950, reasoningTokens: 0, costTotal: 0.2 });
	check("cacheChurn busted high (>0.9)", cacheChurn(busted) > 0.9, cacheChurn(busted));
	const warn = formatReport(busted, { compressionActive: true });
	check("busted + compression => warn", warn.level === "warn", warn.level);
	check("warn explains prefix risk", warn.text.includes("prompt-cache prefix"), warn.text);
	// Same churn but compression OFF must NOT warn (no actor to blame).
	const noBlame = formatReport(busted, { compressionActive: false });
	check("busted + no compression => info", noBlame.level === "info", noBlame.level);

	// Empty accumulator is safe (no div-by-zero, no false warning).
	const empty = emptyAccum();
	check("empty cacheReadRate = 0", cacheReadRate(empty) === 0);
	check("empty report says no billed turns", formatReport(empty, { compressionActive: true }).level === "info");

	// formatStatusLine: empty before any turn, compact + flags on risk.
	check("statusline empty before billed turns", formatStatusLine(empty) === "");
	const okLine = formatStatusLine(healthy, { compressionActive: true });
	check("statusline shows cost + cache", okLine.includes("$") && okLine.includes("cache"), okLine);
	check("statusline healthy has no warn marker", !okLine.includes("⚠"), okLine);
	check("statusline busted+compression has ⚠", formatStatusLine(busted, { compressionActive: true }).includes("⚠"));
	check("statusline busted+no-compression has no ⚠", !formatStatusLine(busted, { compressionActive: false }).includes("⚠"));
}

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
