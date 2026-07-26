// messages.ts — defensive, PURE transforms over OMP's AgentMessage[] for the
// `context` hook. We never depend on the exact (and unstable) AgentMessage
// shape: content is `string | part[]`, and a part may carry text under `.text`
// or `.content`. We only ever READ or REPLACE those string fields — never
// restructure a message — so an unexpected shape degrades to a no-op, never a
// corruption. Unit-tested in scripts/extensions.test.ts.
//
// Sole consumer: extensions/context-compress.ts (opt-in, off by default). The
// former `collapseDuplicateBlobs` export is gone with context-dedup — OMP does
// that natively and cache-aware via `compaction.supersedeReads` (default true)
// + `compaction.dropUseless` (default true) + `pruneToolOutputs`.

import { type Level, compress, estimateTokens } from "./protect.ts";

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
