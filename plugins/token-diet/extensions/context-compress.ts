// context-compress.ts — LOSSY, OPT-IN. The quality-preserving realization of
// caveman-code's LLMLingua/Provence `transformContext`: a protect-masked prose
// compressor over the OLDER assistant/tool messages. Code, paths, numbers and
// identifiers stay byte-identical (the protect mask = LLMLingua `force_tokens`);
// only prose is shortened; the recency window and every user/system message are
// left pristine. OFF unless TOKEN_DIET_CONTEXT_COMPRESS is set to safe|lite|full
// (lossy, so strictly opt-in). See research/caveman-code.md for the heavier
// real-LLMLingua/Provence escalation that reuses the same protect mask.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { compressOldMessages } from "./lib/messages.ts";
import type { Level } from "./lib/protect.ts";

function parseLevel(v: string | undefined): Level | null {
	const s = (v ?? "").toLowerCase();
	return s === "safe" || s === "lite" || s === "full" ? s : null;
}

export default function contextCompress(pi: ExtensionAPI) {
	pi.setLabel("context-compress");
	const level = parseLevel(process.env.TOKEN_DIET_CONTEXT_COMPRESS);
	if (!level) return; // lossy → strictly opt-in

	const minChars = Number(process.env.TOKEN_DIET_COMPRESS_MIN_CHARS ?? 600);
	const keepRecent = Number(process.env.TOKEN_DIET_COMPRESS_KEEP_RECENT ?? 6);

	pi.on("context", async (event) => {
		try {
			compressOldMessages((event as { messages?: unknown }).messages, {
				level,
				minChars,
				keepRecent,
			});
		} catch {
			// passthrough on any surprise — never degrade a request
		}
	});
}
