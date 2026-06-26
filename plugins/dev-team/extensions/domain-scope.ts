// domain-scope.ts — L3 path-scoping companion: a domain-activity signal.
//
// OMP's native rule-buckets already path-scope RULE bodies via `globs:`
// frontmatter (see rules/domain-{backend,frontend,infra}.md) — those load only
// when a matching file is in scope, which IS the real L3 mechanism. This hook
// adds the part globs alone don't give: a once-per-session, per-domain signal
// the first time a domain file is touched — logged for friction measurement
// (the north star) and surfaced as a quiet hint that the domain rule applies.
// Notify-only; it never blocks. Keep DOMAINS in sync with the matching rule's
// `globs:` so the hint and the auto-loaded rule agree.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { appendJSONL, matchesAny, nowISO, pathsFromToolInput, statePath } from "./lib/shared.ts";

// Bare globs (no leading `**/`): shared.ts's matcher anchors each as `(^|/)…$`,
// so these match at any depth against the full path or the basename.
const DOMAINS: Record<string, string[]> = {
	backend: ["*Repository*.*", "*Consumer*.*", "*Controller*.*", "*.sql"],
	frontend: ["*.svelte", "*.tsx", "*.jsx", "*.vue"],
	infra: ["Dockerfile*", "*.tf", "*.tfvars", "*.bicep", "docker-compose*.yml", "docker-compose*.yaml"],
};

export default function domainScope(pi: ExtensionAPI) {
	pi.setLabel("domain-scope");

	const seen = new Set<string>();
	pi.on("session_start", async () => {
		seen.clear();
	});

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") return;
		const paths = pathsFromToolInput(event.toolName, event.input as Record<string, unknown>);
		for (const p of paths) {
			const base = p.split("/").pop() ?? p;
			for (const [domain, globs] of Object.entries(DOMAINS)) {
				if (seen.has(domain)) continue;
				if (matchesAny(p, globs) ?? matchesAny(base, globs)) {
					seen.add(domain);
					try {
						appendJSONL(statePath(ctx.cwd, "domain-scope.jsonl"), {
							ts: nowISO(),
							domain,
							path: p,
						});
					} catch {
						/* best-effort logging — never break a session */
					}
					if (ctx.hasUI) {
						ctx.ui.notify(
							`${domain} file in scope (${base}) — domain-${domain} rule conventions apply.`,
							"info",
						);
					}
				}
			}
		}
	});
}
