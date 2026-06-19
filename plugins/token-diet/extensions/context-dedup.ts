// context-dedup.ts — LOSSLESS. Before each LLM call, collapse byte-identical
// large blocks repeated across assistant/tool messages (keep the most recent
// verbatim, stub earlier copies). Catches duplicates from ANY source — re-reads
// via bash/cat, repeated tool output, verbose MCP payloads — so it is the
// general, source-agnostic complement to read-dedup. Only the LLM-bound copy is
// changed; OMP hands the `context` hook a deep copy, so the saved session is
// untouched. Disable with TOKEN_DIET_CONTEXT_DEDUP=0.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { collapseDuplicateBlobs } from "./lib/messages.ts";

export default function contextDedup(pi: ExtensionAPI) {
	pi.setLabel("context-dedup");
	if (process.env.TOKEN_DIET_CONTEXT_DEDUP === "0") return;
	const minChars = Number(process.env.TOKEN_DIET_DEDUP_MIN_CHARS ?? 1200);

	pi.on("context", async (event) => {
		try {
			collapseDuplicateBlobs(
				(event as { messages?: unknown }).messages,
				minChars,
			);
		} catch {
			// passthrough on any surprise — never degrade a request
		}
	});
}
