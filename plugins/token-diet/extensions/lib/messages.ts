// messages.ts — defensive, PURE transforms over OMP's AgentMessage[] for the
// `context` hook. We never depend on the exact (and unstable) AgentMessage
// shape: content is `string | part[]`, and a part may carry text under `.text`
// or `.content`. We only ever READ or REPLACE those string fields — never
// restructure a message — so an unexpected shape degrades to a no-op, never a
// corruption. Both transforms are unit-tested in scripts/extensions.test.ts.

import { type Level, compress, estimateTokens, sha1 } from "./protect.ts";

// A read/write handle onto one text field somewhere inside a message.
export interface Blob {
	get(): string;
	set(v: string): void;
}

const COMPRESSIBLE_ROLES = new Set(["assistant", "tool"]);

export function messageRole(message: unknown): string {
	return message && typeof message === "object" && "role" in message &&
		typeof (message as { role: unknown }).role === "string"
		? (message as { role: string }).role
		: "";
}

/** Every string text field carried by a message, as get/set handles. */
export function textBlobs(message: unknown): Blob[] {
	const out: Blob[] = [];
	if (!message || typeof message !== "object") return out;
	const msg = message as { content?: unknown };
	const c = msg.content;
	if (typeof c === "string") {
		out.push({ get: () => msg.content as string, set: (v) => { msg.content = v; } });
		return out;
	}
	if (Array.isArray(c)) {
		for (const part of c) {
			if (!part || typeof part !== "object") continue;
			const p = part as { text?: unknown; content?: unknown };
			if (typeof p.text === "string") {
				out.push({ get: () => p.text as string, set: (v) => { p.text = v; } });
			} else if (typeof p.content === "string") {
				out.push({ get: () => p.content as string, set: (v) => { p.content = v; } });
			}
		}
	}
	return out;
}

/**
 * LOSSLESS. Collapse byte-identical large blocks that appear 2+ times across
 * assistant/tool messages: keep the LAST (most recent) occurrence verbatim,
 * replace earlier identical copies with a one-line pointer. Information is
 * retained exactly once, and the canonical copy is present in the same payload,
 * so the model loses nothing. User/system messages are never touched.
 * Returns the estimated tokens saved.
 */
export function collapseDuplicateBlobs(
	messages: unknown,
	minChars: number,
): number {
	if (!Array.isArray(messages)) return 0;
	const byHash = new Map<string, Blob[]>();
	for (const message of messages) {
		if (!COMPRESSIBLE_ROLES.has(messageRole(message))) continue;
		for (const blob of textBlobs(message)) {
			const text = blob.get();
			if (typeof text !== "string" || text.length < minChars) continue;
			const h = sha1(text);
			const arr = byHash.get(h);
			if (arr) arr.push(blob);
			else byHash.set(h, [blob]);
		}
	}
	let saved = 0;
	for (const blobs of byHash.values()) {
		if (blobs.length < 2) continue;
		for (let k = 0; k < blobs.length - 1; k++) {
			const original = blobs[k].get();
			blobs[k].set(
				`[token-diet context-dedup] identical ${original.length}-char block ` +
					`elided — the same content is repeated verbatim later in this ` +
					`context (lossless; disable with TOKEN_DIET_CONTEXT_DEDUP=0).`,
			);
			saved += estimateTokens(original);
		}
	}
	return saved;
}

export interface CompressMessagesOpts {
	level: Level;
	minChars: number;
	/** Leave the most recent N messages pristine (working set fidelity). */
	keepRecent: number;
}

/**
 * LOSSY (opt-in). Run the protect-masked prose compressor over the OLDER
 * assistant/tool messages, leaving the recency window and all user/system
 * messages untouched. Protected detail (code, paths, numbers, identifiers) is
 * byte-identical; only prose is shortened. Returns estimated tokens saved.
 */
export function compressOldMessages(
	messages: unknown,
	opts: CompressMessagesOpts,
): number {
	if (!Array.isArray(messages)) return 0;
	// The recency guarantee applies to the most recent N COMPRESSIBLE messages,
	// not the last N messages overall: counting all roles would let trailing
	// user/system messages push the assistant/tool messages we meant to protect
	// before the cutoff. Walk from the end, counting only compressible messages,
	// and treat everything from there on as protected.
	const keep = Math.max(0, opts.keepRecent);
	let cutoff = messages.length;
	let reserved = 0;
	while (cutoff > 0 && reserved < keep) {
		cutoff--;
		if (COMPRESSIBLE_ROLES.has(messageRole(messages[cutoff]))) reserved++;
	}
	let saved = 0;
	for (let i = 0; i < cutoff; i++) {
		if (!COMPRESSIBLE_ROLES.has(messageRole(messages[i]))) continue;
		for (const blob of textBlobs(messages[i])) {
			const text = blob.get();
			if (typeof text !== "string") continue;
			const out = compress(text, { level: opts.level, minChars: opts.minChars });
			if (out.length < text.length) {
				blob.set(out);
				saved += estimateTokens(text) - estimateTokens(out);
			}
		}
	}
	return saved;
}

// Harmless default export in case extension discovery scans lib/ as an entry.
export default function () {}
