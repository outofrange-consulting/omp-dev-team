// Turn a Plan into (a) an OMP provider config for pi.registerProvider, (b) the
// role wiring YAML, and (c) summaries/JSON. Provider is named "local-llm" so
// model ids are local-llm/<servedId>.
//
// ROLE POLICY (the important bit): local models are conservative by default —
// they only take the cheap/high-volume roles. Heavier roles move to local only
// as you raise the level AND a strong-enough model actually fits:
//   smol        → smol/commit/vision local; everything else stays cloud (DEFAULT)
//   balanced    → + task/slow local IF a high-quality model fits (not a spill)
//   max         → + default local IF a top model fits FULLY on the GPU (oncard)
//   local-only  → everything local (plan/default too) — power users
// plan always stays on cloud unless local-only.

import type { Fit, Plan } from "./selector.ts";

export type Backend = "ollama" | "llama.cpp";
export type Level = "smol" | "balanced" | "max" | "local-only";
export const PROVIDER = "local-llm";
export const LEVELS: Level[] = ["smol", "balanced", "max", "local-only"];

// Quality bars (0..100) a local model must clear to earn a heavier role.
const TASK_MIN_Q = 78; // agentic execution subagents
const SLOW_MIN_Q = 80; // quality-over-speed
const DEFAULT_MIN_Q = 85; // the everyday driver — only on a big config

export const BACKENDS: Record<Backend, { baseUrl: string; api: string }> = {
	ollama: { baseUrl: "http://127.0.0.1:11434", api: "openai-responses" },
	"llama.cpp": { baseUrl: "http://127.0.0.1:8080/v1", api: "openai-completions" },
};

function servedId(f: Fit, backend: Backend): string {
	return backend === "ollama" ? f.model.pull : f.model.id;
}

export interface ProviderConfig {
	baseUrl: string;
	api: string;
	auth: "none";
	compat: Record<string, unknown>;
	models: Array<Record<string, unknown>>;
}

export function providerConfig(plan: Plan, backend: Backend = "ollama"): ProviderConfig {
	const be = BACKENDS[backend];
	return {
		baseUrl: be.baseUrl,
		api: be.api,
		auth: "none",
		compat: { toolStrictMode: "none", supportsUsageInStreaming: true },
		models: plan.available.map((f) => {
			const m = f.model;
			const compat: Record<string, unknown> = {};
			if (m.thinkingFormat) compat.thinkingFormat = m.thinkingFormat;
			if (m.id.startsWith("devstral")) {
				compat.requiresToolResultName = true;
				compat.requiresMistralToolIds = true;
			}
			return {
				id: servedId(f, backend),
				name: `${m.name} [${f.mode}]`,
				reasoning: m.reasoning,
				input: m.input,
				contextWindow: m.contextWindow,
				maxTokens: 32768,
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
				...(Object.keys(compat).length ? { compat } : {}),
			};
		}),
	};
}

export interface RoleAssign {
	role: string;
	target: string; // model ref written into modelRoles
	local: boolean;
	modelId?: string; // catalog id, when local (for pulls)
	note?: string;
}

// Decide, per role, whether a local model is good enough at this level — else cloud.
export function assignRoles(
	plan: Plan,
	opts: { backend?: Backend; level?: Level; cloud?: string },
): RoleAssign[] {
	const backend = opts.backend ?? "ollama";
	const level = opts.level ?? "smol";
	const cloud = opts.cloud ?? "anthropic/claude-opus-4-8";
	const localOnly = level === "local-only";
	const fit = (role: string): Fit | undefined => {
		const id = plan.roles[role as keyof Plan["roles"]];
		return id ? plan.available.find((x) => x.model.id === id) : undefined;
	};
	const lref = (f: Fit) => `${PROVIDER}/${servedId(f, backend)}`;
	const localPick = (role: string, f: Fit | undefined, note?: string): RoleAssign =>
		({ role, target: lref(f as Fit), local: true, modelId: (f as Fit).model.id, note });
	const cloudPick = (role: string, suffix = ""): RoleAssign =>
		({ role, target: `${cloud}${suffix}`, local: false });
	const best = plan.available[0];
	const out: RoleAssign[] = [];

	// plan — cloud unless local-only.
	out.push(localOnly && best ? localPick("plan", best) : cloudPick("plan", ":high"));

	// default — only local on a "big config": a top model resident fully on the GPU.
	const df = fit("default");
	if (localOnly && (df || best)) out.push(localPick("default", df || best));
	else if (df && df.mode === "oncard" && df.model.quality >= DEFAULT_MIN_Q && (level === "max"))
		out.push(localPick("default", df, "big-config: top model fully on GPU"));
	else out.push(cloudPick("default"));

	// task — local from "balanced" up, if a strong model fits without spilling.
	const tf = fit("task");
	if (tf && (localOnly || (level !== "smol" && tf.model.quality >= TASK_MIN_Q && tf.mode !== "dense-spill")))
		out.push(localPick("task", tf));
	else out.push(cloudPick("task"));

	// slow — local from "balanced" up, if quality clears the bar (offload ok).
	const sf = fit("slow");
	if (sf && (localOnly || (level !== "smol" && sf.model.quality >= SLOW_MIN_Q)))
		out.push(localPick("slow", sf));
	// (no cloud fallback line for slow — OMP falls back to default if unset)

	// smol / commit / vision — always local when something fits (the whole point).
	for (const r of ["smol", "commit", "vision"]) {
		const f = fit(r);
		if (f) out.push(localPick(r, f));
	}
	return out;
}

export function rolesYaml(plan: Plan, opts: { backend?: Backend; level?: Level; cloud?: string } = {}): string {
	const a = assignRoles(plan, opts);
	const cloud = opts.cloud ?? "anthropic/claude-opus-4-8";
	const lines = ["modelRoles:"];
	for (const r of a) lines.push(`  ${r.role}: ${r.target}${r.local ? "" : "   # cloud"}${r.note ? `  # ${r.note}` : ""}`);
	const localUsed = [...new Set(a.filter((x) => x.local).map((x) => x.target))];
	lines.push("", "enabledModels:", `  - ${cloud}`, ...localUsed.map((t) => `  - ${t}`));
	lines.push("", "modelProviderOrder:", `  - ${PROVIDER}`, "  - ollama", "  - anthropic");
	return lines.join("\n");
}

export function planSummary(plan: Plan, source: string, opts: { backend?: Backend; level?: Level } = {}): string {
	const hw = plan.hardware;
	const level = opts.level ?? "smol";
	const a = assignRoles(plan, opts);
	const lines = [
		`# local-llm plan — ${hw.vramGB}GB VRAM / ${hw.ramGB}GB RAM (via ${source}) · level: ${level}`,
		"",
		`Fitting models (${plan.available.length}):`,
		...plan.available.map((f) => `  ${f.mode === "oncard" ? "🟢" : f.mode === "moe-offload" ? "🟡" : "🟠"} ${f.model.name} [${f.mode}] q=${f.model.quality}`),
		"",
		"Role wiring (cloud stays for the heavy roles unless your box earns local):",
		...a.map((r) => `  ${r.role.padEnd(8)} → ${r.local ? r.target : `${r.target}  (cloud)`}${r.note ? `   # ${r.note}` : ""}`),
		"",
		level === "smol"
			? "Conservative default: only smol/commit/vision run local. Raise --level=balanced (task/slow), max (default), or local-only."
			: `Level ${level}. Lower with --level=smol to keep only the cheap roles local.`,
	];
	return lines.join("\n");
}

export function planJson(plan: Plan, backend: Backend, level: Level = "smol"): string {
	const a = assignRoles(plan, { backend, level });
	const usedIds = new Set(a.filter((x) => x.local && x.modelId).map((x) => x.modelId));
	const byId = (id?: string) => plan.available.find((f) => f.model.id === id);
	const pulls = [...usedIds].map((id) => byId(id)?.model.pull).filter(Boolean);
	const pullsAll = [...new Set(plan.available.map((f) => f.model.pull))];
	return JSON.stringify(
		{ backend, level, hardware: plan.hardware, pulls, pullsAll, assignment: a, rolesYaml: rolesYaml(plan, { backend, level }) },
		null,
		2,
	);
}

export default function () {}
