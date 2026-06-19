// read-dedup.ts — suppress byte-identical re-reads of unchanged files while the
// original is still in live context. LOSSLESS: the earlier read's bytes are
// still present, so the stub just points back at them. Compaction-aware: the
// seen-set is cleared on compaction (which can evict the original), so the next
// re-read runs normally and repopulates context. Port of caveman-code's
// "Read Dedup" layer, adapted to OMP's tool_call gate.
// Disable with TOKEN_DIET_READ_DEDUP=0.

import { statSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export default function readDedup(pi: ExtensionAPI) {
	pi.setLabel("read-dedup");
	if (process.env.TOKEN_DIET_READ_DEDUP === "0") return;

	let seen = new Set<string>();
	const reset = () => {
		seen = new Set();
	};
	// New session, or any compaction that may have evicted the original read.
	pi.on("session_start", async () => reset());
	pi.on("session_compact", async () => reset());
	pi.on("auto_compaction_end", async () => reset());

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "read") return;
		const input = (event.input ?? {}) as Record<string, unknown>;
		const path = typeof input.path === "string" ? input.path : undefined;
		if (!path) return;

		let fp: string;
		try {
			const abs = isAbsolute(path) ? path : join(ctx.cwd, path);
			const st = statSync(abs);
			fp = `${st.size}:${st.mtimeMs}`;
		} catch {
			return; // can't stat (virtual path, perms, race) — never interfere
		}

		// Signature includes ALL input params (offset/limit/range/…) so a
		// different slice of the same file is never treated as a duplicate, and
		// the file fingerprint so an edit between reads lets the re-read through.
		const sig = `${JSON.stringify(input)}::${fp}`;
		if (seen.has(sig)) {
			return {
				block: true,
				reason:
					`[token-diet read-dedup] "${path}" is byte-identical to an earlier ` +
					`read this session and that content is still in context — reuse it ` +
					`instead of re-reading. (An edit since then, or compaction, lets a ` +
					`re-read through. Disable: TOKEN_DIET_READ_DEDUP=0.)`,
			};
		}
		seen.add(sig);
	});
}
