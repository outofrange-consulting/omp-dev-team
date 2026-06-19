// context-compress.ts — the quality-preserving realization of caveman-code's
// LLMLingua/Provence `transformContext`: a protect-masked prose compressor over
// the OLDER assistant/tool messages. Code, paths, numbers and identifiers stay
// byte-identical (the protect mask = LLMLingua `force_tokens`); only prose is
// shortened; the recency window and every user/system message are left pristine.
//
// Default level is `safe` (near-lossless: strips ANSI + trailing/again-collapsed
// whitespace only, never drops words) — ON by default. `lite`/`full` additionally
// drop filler/articles (lossy) and are opt-in. Disable entirely with
// TOKEN_DIET_CONTEXT_COMPRESS=off. See research/caveman-code.md for the heavier
// real-LLMLingua/Provence escalation that reuses the same protect mask.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { compressOldMessages } from "./lib/messages.ts";
import type { Level } from "./lib/protect.ts";

// Unset/blank/unknown → "safe" (on); off|0|none|false → null (disabled).
export function parseLevel(v: string | undefined): Level | null {
	const s = (v ?? "").trim().toLowerCase();
	if (s === "off" || s === "0" || s === "none" || s === "false") return null;
	if (s === "lite" || s === "full") return s;
	return "safe";
}

export default function contextCompress(pi: ExtensionAPI) {
	pi.setLabel("context-compress");
	const level = parseLevel(process.env.TOKEN_DIET_CONTEXT_COMPRESS);
	if (!level) return; // disabled via TOKEN_DIET_CONTEXT_COMPRESS=off

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
