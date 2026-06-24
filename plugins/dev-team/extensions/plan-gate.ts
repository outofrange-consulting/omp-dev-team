// plan-gate.ts — enforces the dev-team pipeline ORDER for source edits:
//
//     pre-analysis (/scope) -> trivial | plan (/plan-approve) -> build -> review
//
// It blocks edits/writes to production SOURCE until the task has been scoped and
// either marked trivial or had a plan approved. This forces BOTH the agent and
// the human through the plan step — it is enforcement (PreToolUse block), not
// prose the agent may choose to honor. The review step is enforced separately by
// review-gate (blocks the commit). Together: scope -> plan -> build -> review.
//
// This replaces test-first (TDD) enforcement: test-first ordering adds little for
// AI agents, so the leverage moves to a stronger plan gate. Tests are still
// required and verified by /impl-verify — just not test-first (see the
// `tests-required` rule).
//
// Gated surface: production source only. Docs, config, specs (.feature), and
// tests are NEVER gated — writing a README, a config value, a behavioral spec, or
// a test before a plan is fine. Only implementing source is gated.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	bashWriteTargets,
	pathsFromToolInput,
	readState,
	writeState,
} from "./lib/shared.ts";

const SOURCE_RE =
	/\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|java|kt|rb|php|cs|swift|scala|c|cc|cpp|h|hpp|m|mm|svelte|vue)$/i;
const TEST_RE = /(\.|_|\/)(test|spec)\.|(^|\/)(tests?|__tests__|spec)\//i;

// A path is gated iff it is production source (not a test, not docs/config/spec).
export function isGatedSource(p: string): boolean {
	return SOURCE_RE.test(p) && !TEST_RE.test(p);
}

// Pipeline stage, persisted out-of-tree so /build subagents inherit it.
//   undefined   — not yet scoped (pre-analysis missing)
//   needs-plan  — scoped non-trivial; awaiting an approved plan
//   trivial     — scoped trivial; source edits allowed
//   plan-approved — a plan was approved; source edits allowed
export type Stage = "needs-plan" | "trivial" | "plan-approved";
// Task size from the pre-analysis, also consumed by model-routing (effort-band).
export type Size = "trivial" | "standard" | "complex";
interface PlanGateState {
	stage?: Stage;
	size?: Size;
	planPath?: string;
	at?: string;
}

export type Decision = "allow" | "need-scope" | "need-plan";

// Pure decision for a gated source edit, given the current stage.
export function gateDecision(stage: Stage | undefined): Decision {
	if (stage === "trivial" || stage === "plan-approved") return "allow";
	if (stage === "needs-plan") return "need-plan";
	return "need-scope";
}

export default function planGate(pi: ExtensionAPI) {
	pi.setLabel("plan-gate");

	const set = (cwd: string, stage: Stage, size: Size, planPath?: string) =>
		writeState(cwd, "plan-gate.json", {
			stage,
			size,
			planPath,
			at: new Date().toISOString(),
		} satisfies PlanGateState);

	pi.registerCommand("scope", {
		description:
			"Pre-analysis: classify the task per the task-size-classifier. Usage: /scope [--trivial | --complex]",
		handler: async (args, ctx) => {
			const a = ` ${args ?? ""} `;
			if (/(^|\s)--trivial(\s|$)/.test(a)) {
				set(ctx.cwd, "trivial", "trivial");
				ctx.ui.notify(
					"scoped TRIVIAL — fast path: source edits unlocked; agents may downshift a band. /plan-reset to re-arm.",
					"warn",
				);
			} else {
				const size: Size = /(^|\s)--complex(\s|$)/.test(a) ? "complex" : "standard";
				set(ctx.cwd, "needs-plan", size);
				ctx.ui.notify(
					`scoped NON-TRIVIAL (${size}) — draft a plan with /plan, get human sign-off, then /plan-approve to unlock implementation.`,
					"info",
				);
			}
		},
	});

	pi.registerCommand("trivial", {
		description:
			"Shortcut for /scope --trivial: mark the current task trivial and unlock source edits",
		handler: async (_args, ctx) => {
			set(ctx.cwd, "trivial", "trivial");
			ctx.ui.notify(
				"scoped TRIVIAL — source edits unlocked for this task. /plan-reset to re-arm.",
				"warn",
			);
		},
	});

	pi.registerCommand("plan-approve", {
		description:
			"Approve the current plan — unlock implementation (source edits). Requires the task to be scoped non-trivial first.",
		handler: async (args, ctx) => {
			const st = readState<PlanGateState>(ctx.cwd, "plan-gate.json", {});
			if (st.stage === undefined) {
				ctx.ui.notify(
					"run /scope first (pre-analysis) — a plan can't be approved before the task is scoped.",
					"warn",
				);
				return;
			}
			const planPath = (args ?? "").trim() || st.planPath;
			set(ctx.cwd, "plan-approved", st.size ?? "standard", planPath);
			ctx.ui.notify(
				`plan approved${planPath ? ` (${planPath})` : ""} — implementation unlocked`,
				"info",
			);
		},
	});

	pi.registerCommand("plan-reset", {
		description:
			"Re-arm the gate: clear scope/approval so the next task must go scope -> plan again",
		handler: async (_args, ctx) => {
			writeState(ctx.cwd, "plan-gate.json", {} satisfies PlanGateState);
			ctx.ui.notify(
				"plan gate re-armed — next source edit requires /scope then (if non-trivial) /plan-approve.",
				"warn",
			);
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		const tool = event.toolName;
		let targets: string[] = [];
		if (tool === "write" || tool === "edit") {
			targets = pathsFromToolInput(tool, event.input as Record<string, unknown>);
		} else if (tool === "bash") {
			targets = bashWriteTargets(
				String((event.input as Record<string, unknown>).command ?? ""),
			);
		} else {
			return;
		}

		const gated = targets.filter(isGatedSource);
		if (gated.length === 0) return; // docs/config/spec/test — never gated

		const st = readState<PlanGateState>(ctx.cwd, "plan-gate.json", {});
		const decision = gateDecision(st.stage);
		if (decision === "allow") return;

		if (decision === "need-scope") {
			return {
				block: true,
				reason:
					`Plan gate: editing source ("${gated[0]}") before pre-analysis.\n` +
					`Pipeline order is enforced: pre-analysis -> (trivial | plan) -> build -> review.\n` +
					`Run /scope first. Trivial change (typo, comment, one-line doc/config) -> ` +
					`/scope --trivial (or /trivial). Otherwise -> /plan, get sign-off, /plan-approve.\n` +
					`Docs, config, specs, and tests are never gated.`,
			};
		}
		return {
			block: true,
			reason:
				`Plan gate: this task is scoped NON-TRIVIAL — implementing source ("${gated[0]}") ` +
				`needs an approved plan.\n` +
				`Draft it with /plan, get human sign-off, then /plan-approve to unlock the build.`,
		};
	});
}
