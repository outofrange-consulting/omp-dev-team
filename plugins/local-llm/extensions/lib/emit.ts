// Turn a Plan into (a) an OMP provider config for pi.registerProvider, (b) the
// models.yml + settings YAML to persist, and (c) human/JSON summaries. The
// provider is named "local-llm" so model ids are local-llm/<servedId>.

import type { Fit, Plan } from "./selector.ts";

export type Backend = "ollama" | "llama.cpp";
export const PROVIDER = "local-llm";

export const BACKENDS: Record<Backend, { baseUrl: string; api: string }> = {
	// Ollama new engine speaks the responses API and auto-discovers on :11434.
	ollama: { baseUrl: "http://127.0.0.1:11434", api: "openai-responses" },
	// llama-server (OpenAI-completions compatible) on :8080.
	"llama.cpp": { baseUrl: "http://127.0.0.1:8080/v1", api: "openai-completions" },
};

// The id the backend actually serves: ollama uses the pull tag, llama.cpp the id.
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

// modelRoles + enabledModels + modelProviderOrder. Hybrid by default: heavy
// planning stays on cloud; execution/cheap roles go local. localOnly=true puts
// default+plan local too.
export function rolesYaml(plan: Plan, opts: { backend?: Backend; localOnly?: boolean; cloudPlan?: string } = {}): string {
	const backend = opts.backend ?? "ollama";
	const cloud = opts.cloudPlan ?? "anthropic/claude-opus-4-8";
	const ref = (role: keyof Plan["roles"]): string | undefined => {
		const id = plan.roles[role];
		if (!id) return undefined;
		const f = plan.available.find((x) => x.model.id === id);
		return f ? `${PROVIDER}/${servedId(f, backend)}` : undefined;
	};
	const lines: string[] = ["modelRoles:"];
	if (opts.localOnly && ref("default")) {
		lines.push(`  plan: ${ref("default")}`, `  default: ${ref("default")}`);
	} else {
		lines.push(`  plan: ${cloud}:high      # cloud — local can't match deep planning yet`, `  default: ${cloud}`);
	}
	for (const role of ["task", "smol", "commit", "slow", "vision"] as const) {
		const r = ref(role);
		if (r) lines.push(`  ${role}: ${r}`);
	}
	const enabled = [cloud, ...plan.available.map((f) => `${PROVIDER}/${servedId(f, backend)}`)];
	lines.push("", "enabledModels:");
	for (const e of enabled) lines.push(`  - ${e}`);
	lines.push("", "modelProviderOrder:", `  - ${PROVIDER}`, "  - ollama", "  - anthropic");
	return lines.join("\n");
}

export function planSummary(plan: Plan, source: string): string {
	const hw = plan.hardware;
	const lines = [
		`# local-llm plan — ${hw.vramGB}GB VRAM / ${hw.ramGB}GB RAM (detected via ${source})`,
		"",
		`Fitting models (${plan.available.length}):`,
		...plan.available.map((f) => `  ${f.mode === "oncard" ? "🟢" : f.mode === "moe-offload" ? "🟡" : "🟠"} ${f.model.name} [${f.mode}] q=${f.model.quality} (${f.detail})`),
		"",
		"Role assignment:",
		...plan.rationale.map((r) => `  ${r}`),
	];
	return lines.join("\n");
}

// Machine-readable plan for the install script (which models to pull, etc.).
export function planJson(plan: Plan, backend: Backend): string {
	return JSON.stringify(
		{
			backend,
			hardware: plan.hardware,
			pulls: plan.available.map((f) => ({ id: f.model.id, pull: f.model.pull, mode: f.mode, hf: f.model.hf })),
			roles: plan.roles,
			rolesYaml: rolesYaml(plan, { backend }),
		},
		null,
		2,
	);
}

export default function () {}
