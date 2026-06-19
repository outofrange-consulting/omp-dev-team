// Unit tests for token-diet's pure context-transform logic.
//   bun plugins/token-diet/scripts/extensions.test.ts
// No OMP dependency — exercises the quality-critical invariants directly:
// protect/restore is lossless, compression preserves every technical detail,
// the activation threshold + never-expand guards hold, and the message-array
// transforms (lossless dedup, lossy recency-preserving compress) behave.

import {
	type Level,
	compress,
	protect,
	restore,
} from "../extensions/lib/protect.ts";
import {
	collapseDuplicateBlobs,
	compressOldMessages,
	textBlobs,
} from "../extensions/lib/messages.ts";

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

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
