// context-compress.ts — the quality-preserving realization of caveman-code's
// LLMLingua/Provence `transformContext`: a protect-masked prose compressor over
// the OLDER assistant/tool messages. Code, paths, numbers and identifiers stay
// byte-identical (the protect mask = LLMLingua `force_tokens`); only prose is
// shortened; the recency window and every user/system message are left pristine.
//
// OFF BY DEFAULT — opt in with TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full.
//
// Why off: at `safe` the whole job (strip ANSI, collapse whitespace) is already
// done at the source — every OMP shellMinimizer filter opens with strip_ansi,
// and NO_COLOR=1 / TERM=dumb mean ANSI mostly never arrives. Worse, keepRecent
// is a SLIDING window, so on every turn one more message flips from pristine to
// compressed: a recurring byte change inside the already-sent prefix, which is
// exactly what busts the provider prompt cache (cached input is ~10x cheaper
// than fresh input, so a bust costs far more than the bytes saved).
//
// Turn it on only for a long, prose-heavy session where you have measured the
// cache-read ratio and confirmed compaction is not already handling it.
//
// `lite`/`full` additionally drop filler/articles and ARE lossy.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { compressOldMessages } from "./lib/messages.ts";
import type { Level } from "./lib/protect.ts";

// Unset/blank/off/unknown → null (disabled); safe|lite|full → that level.
export function parseLevel(v: string | undefined): Level | null {
	const s = (v ?? "").trim().toLowerCase();
	if (s === "safe" || s === "lite" || s === "full") return s;
	return null;
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
