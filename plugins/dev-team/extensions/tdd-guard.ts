// tdd-guard.ts — advisory RED-GREEN-REFACTOR nudge. Port of the Claude Code
// `tdd-guard.sh` PostToolUse hook (advisory, non-blocking).
//
// Tracks whether a test file has been touched this session before source files
// are edited, and nudges once when source is changed test-first discipline is
// not visible. Never blocks — TDD is enforced by the orchestrator/build flow.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { pathsFromToolInput } from "./lib/shared.ts";

const TEST_RE = /(\.|_|\/)(test|spec)\.|(^|\/)(tests?|__tests__|spec)\//i;
const SOURCE_RE = /\.(ts|tsx|js|jsx|py|go|rs|java|kt|cs|rb|svelte|vue)$/i;

export default function tddGuard(pi: ExtensionAPI) {
	pi.setLabel("tdd-guard");

	let sawTest = false;
	let nudged = false;

	pi.on("session_start", async () => {
		sawTest = false;
		nudged = false;
	});

	pi.on("tool_result", async (event, ctx) => {
		if (event.isError) return;
		if (event.toolName !== "write" && event.toolName !== "edit") return;
		const paths = pathsFromToolInput(
			event.toolName,
			event.input as Record<string, unknown>,
		);
		for (const p of paths) {
			if (TEST_RE.test(p)) {
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
