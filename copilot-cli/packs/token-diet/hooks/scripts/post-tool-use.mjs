#!/usr/bin/env node
// post-tool-use.mjs — token-diet output compression for GitHub Copilot CLI.
//
// ctx-wire already compresses *shell* output transparently via PATH shims (it is
// CLI-agnostic). This Copilot CLI `postToolUse` hook covers the rest — the output
// of non-shell tools — by:
//   1. scrubbing common secrets (defense in depth; mirrors ctx-wire's scrub pass),
//   2. collapsing runs of blank lines,
//   3. head/tail-truncating very large outputs (keeps the signal, drops the bulk).
//
// It returns {modifiedResult} only when it actually shrank the text, so untouched
// output passes through byte-for-byte. Lossy truncation is clearly marked.
//
// Tuning via env: TOKEN_DIET_MAX_LINES (default 400), TOKEN_DIET_HEAD (default
// 200), TOKEN_DIET_TAIL (default 120), TOKEN_DIET_DISABLE=1 to pass through.

import { readFileSync } from "node:fs";

const MAX_LINES = int(process.env.TOKEN_DIET_MAX_LINES, 400);
const HEAD = int(process.env.TOKEN_DIET_HEAD, 200);
const TAIL = int(process.env.TOKEN_DIET_TAIL, 120);

function int(v, d) {
	const n = Number.parseInt(v ?? "", 10);
	return Number.isFinite(n) && n > 0 ? n : d;
}

let raw = "";
try {
	raw = readFileSync(0, "utf8");
} catch {
	process.exit(0);
}
if (!raw || process.env.TOKEN_DIET_DISABLE === "1") process.exit(0);

let payload;
try {
	payload = JSON.parse(raw);
} catch {
	process.exit(0);
}

// Locate the LLM-facing text of the tool result across plausible shapes.
const result = payload.toolResult ?? {};
const original =
	typeof result.textResultForLlm === "string"
		? result.textResultForLlm
		: typeof result.text === "string"
			? result.text
			: typeof result.output === "string"
				? result.output
				: null;
if (original == null) process.exit(0);

const compressed = compress(original);
if (compressed === original) process.exit(0);

const modifiedResult = { ...result };
if ("textResultForLlm" in result) modifiedResult.textResultForLlm = compressed;
else if ("text" in result) modifiedResult.text = compressed;
else if ("output" in result) modifiedResult.output = compressed;
if (!modifiedResult.resultType) modifiedResult.resultType = "success";

process.stdout.write(`${JSON.stringify({ modifiedResult })}\n`);

function compress(text) {
	let t = scrubSecrets(text);
	// collapse 3+ blank lines to one.
	t = t.replace(/\n[ \t]*\n([ \t]*\n)+/g, "\n\n");
	const lines = t.split("\n");
	if (lines.length > MAX_LINES) {
		const head = lines.slice(0, HEAD);
		const tail = lines.slice(-TAIL);
		const dropped = lines.length - HEAD - TAIL;
		t = [
			...head,
			"",
			`… [token-diet: trimmed ${dropped} of ${lines.length} lines — middle omitted] …`,
			"",
			...tail,
		].join("\n");
	}
	return t;
}

// Conservative secret scrub. Mirrors the high-confidence shapes ctx-wire redacts
// (PEM keys, JWTs, provider tokens, Authorization headers, URL credentials).
function scrubSecrets(text) {
	const R = "[redacted]";
	return text
		.replace(/-----BEGIN (?:RSA |EC |OPENSSH |PGP |DSA )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH |PGP |DSA )?PRIVATE KEY-----/g, `-----BEGIN PRIVATE KEY----- ${R} -----END PRIVATE KEY-----`)
		.replace(/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b/g, R) // JWT
		.replace(/\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b/g, R) // GitHub tokens
		.replace(/\bgithub_pat_[A-Za-z0-9_]{20,}\b/g, R)
		.replace(/\b(?:AKIA|ASIA)[A-Z0-9]{12,}\b/g, R) // AWS access key id
		.replace(/\bAIza[A-Za-z0-9_-]{20,}\b/g, R) // Google API key
		.replace(/\bxox[baprs]-[A-Za-z0-9-]{10,}\b/g, R) // Slack
		.replace(/\bsk-[A-Za-z0-9]{20,}\b/g, R) // OpenAI-style
		.replace(/\bATATT[A-Za-z0-9_=-]{10,}\b/g, R) // Atlassian API token
		.replace(/(Authorization:\s*(?:Bearer|Basic|token)\s+)[A-Za-z0-9._~+/=-]+/gi, `$1${R}`)
		.replace(/\b([a-z][a-z0-9+.-]*:\/\/[^\s:@/]+):([^\s:@/]+)@/gi, `$1:${R}@`); // url creds
}
