// tdd-guard.ts — (1) BLOCKS edits to existing .feature BDD specs so agents fix
// the CODE instead of rewriting the test to pass, and (2) an advisory
// RED-GREEN-REFACTOR nudge when source changes before any test is touched.
//
// Authoring a brand-new .feature is allowed; only modifying/overwriting an
// existing one (via edit/write/shell) is blocked. Opt out for a session with
// /allow-feature-edits (or OMP_ALLOW_FEATURE_EDITS=1); re-protect with
// /protect-features. Deliberate spec changes should go through /specs.

import { existsSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { pathsFromToolInput } from "./lib/shared.ts";

const TEST_RE = /(\.|_|\/)(test|spec)\.|(^|\/)(tests?|__tests__|spec)\//i;
const SOURCE_RE = /\.(ts|tsx|js|jsx|py|go|rs|java|kt|cs|rb|svelte|vue)$/i;
const FEATURE_RE = /\.feature$/i;
// shell ops that would mutate a file
const BASH_WRITE_RE = /(>>?|\btee\b|sed\s+-i|\bmv\b|\bcp\b|\brm\b|\btruncate\b|\bdd\b)/i;

function featureReason(p: string): string {
	return (
		`Blocked edit of BDD spec "${p}". Fix the CODE to satisfy the spec — don't ` +
		`change the test to make it pass.\n` +
		`If the spec itself is genuinely wrong, change it deliberately via /specs, or ` +
		`temporarily allow with /allow-feature-edits (or OMP_ALLOW_FEATURE_EDITS=1). ` +
		`Re-protect with /protect-features.`
	);
}

export default function tddGuard(pi: ExtensionAPI) {
	pi.setLabel("tdd-guard");

	let sawTest = false;
	let nudged = false;
	let allowFeatureEdits = false;

	const fileExists = (cwd: string, p: string) =>
		existsSync(isAbsolute(p) ? p : join(cwd, p)) || existsSync(p);

	pi.on("session_start", async () => {
		sawTest = false;
		nudged = false;
		allowFeatureEdits = /^(1|true|yes|on)$/i.test(process.env.OMP_ALLOW_FEATURE_EDITS ?? "");
	});

	// (1) Block edits to existing .feature specs (pre-execution).
	pi.on("tool_call", async (event, ctx) => {
		if (allowFeatureEdits) return;
		const tool = event.toolName;
		if (tool === "write" || tool === "edit") {
			const paths = pathsFromToolInput(tool, event.input as Record<string, unknown>);
			for (const p of paths) {
				if (!FEATURE_RE.test(p)) continue;
				// edit always targets an existing file; write only blocks an overwrite
				// (authoring a new spec is fine).
				if (tool === "edit" || fileExists(ctx.cwd, p)) {
					return { block: true, reason: featureReason(p) };
				}
			}
			return;
		}
		if (tool === "bash") {
			const cmd = String((event.input as Record<string, unknown>).command ?? "");
			if (/\.feature\b/i.test(cmd) && BASH_WRITE_RE.test(cmd)) {
				return { block: true, reason: `${featureReason("(.feature via shell)")}\nCommand: ${cmd}` };
			}
		}
	});

	pi.registerCommand("allow-feature-edits", {
		description: "Allow editing .feature BDD specs for this session (TDD guard)",
		handler: async (_args, ctx) => {
			allowFeatureEdits = true;
			ctx.ui.notify(".feature edits ALLOWED this session — change specs deliberately. Re-protect with /protect-features.", "warn");
		},
	});
	pi.registerCommand("protect-features", {
		description: "Re-block editing .feature BDD specs (TDD guard)",
		handler: async (_args, ctx) => {
			allowFeatureEdits = false;
			ctx.ui.notify(".feature specs protected again (edits blocked).", "info");
		},
	});

	// (2) Advisory RED-GREEN-REFACTOR nudge (post-execution, never blocks).
	pi.on("tool_result", async (event, ctx) => {
		if (event.isError) return;
		if (event.toolName !== "write" && event.toolName !== "edit") return;
		const paths = pathsFromToolInput(event.toolName, event.input as Record<string, unknown>);
		for (const p of paths) {
			if (TEST_RE.test(p) || FEATURE_RE.test(p)) {
				sawTest = true;
				return;
			}
		}
		const editedSource = paths.some((p) => SOURCE_RE.test(p) && !TEST_RE.test(p));
		if (editedSource && !sawTest && !nudged) {
			nudged = true;
			ctx.ui.notify(
				"TDD: source changed but no test edited yet this session — " +
					"write a failing test first (RED → GREEN → REFACTOR).",
				"warn",
			);
		}
	});
}
