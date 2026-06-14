// local-llm — detect VRAM/RAM, pick the best-fit local models, register them as
// the `local-llm` provider, and print the role wiring. The same selection logic
// powers the CLI the install script calls (`bun local-llm.ts --json`).

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { detectHardware } from "./lib/detect.ts";
import { buildPlan } from "./lib/selector.ts";
import { type Backend, PROVIDER, planJson, planSummary, providerConfig, rolesYaml } from "./lib/emit.ts";

async function probe(url: string): Promise<boolean> {
	try {
		const c = new AbortController();
		const t = setTimeout(() => c.abort(), 600);
		const r = await fetch(url, { signal: c.signal });
		clearTimeout(t);
		return r.ok;
	} catch {
		return false;
	}
}

async function pickBackend(): Promise<Backend> {
	const env = process.env.OMP_LOCAL_BACKEND;
	if (env === "ollama" || env === "llama.cpp") return env;
	if (await probe("http://127.0.0.1:8080/v1/models")) return "llama.cpp";
	if (await probe("http://127.0.0.1:11434/api/tags")) return "ollama";
	return "ollama";
}

async function apply(pi: ExtensionAPI): Promise<string> {
	const hw = await detectHardware();
	const plan = buildPlan(hw);
	if (!plan.available.length) {
		return `local-llm: no catalog model fits ${hw.vramGB}GB VRAM / ${hw.ramGB}GB RAM (≥8GB VRAM recommended). Nothing registered.`;
	}
	const backend = await pickBackend();
	try {
		// Register the fitting local models live (no reload). Older hosts without
		// registerProvider just skip this; the role YAML below still works.
		(pi as unknown as { registerProvider?: (n: string, c: unknown) => void }).registerProvider?.(
			PROVIDER,
			providerConfig(plan, backend),
		);
	} catch {
		/* provider registration optional */
	}
	return [
		planSummary(plan, hw.source),
		"",
		`Backend: ${backend}. Paste into ~/.omp/agent/config.yml to wire roles:`,
		"",
		rolesYaml(plan, { backend }),
	].join("\n");
}

export default function localLlm(pi: ExtensionAPI) {
	pi.setLabel("local-llm");
	// Register best-fit local models at startup so they're immediately usable.
	void apply(pi).catch(() => {});
	pi.registerCommand("local-llm", {
		description: "Detect VRAM/RAM and (re)register the best-fit local models + print role wiring",
		handler: async (_args, ctx) => {
			const out = await apply(pi);
			ctx.ui.notify(out, "info");
		},
	});
}

// ---- Standalone CLI (used by install.sh): bun local-llm.ts [--json] [--vram N --ram N --backend ollama|llama.cpp]
if (import.meta.main) {
	const args = process.argv.slice(2);
	const arg = (k: string) => {
		const i = args.indexOf(k);
		return i >= 0 ? args[i + 1] : undefined;
	};
	const vram = arg("--vram") ? Number(arg("--vram")) : undefined;
	const ram = arg("--ram") ? Number(arg("--ram")) : undefined;
	const backend = (arg("--backend") as Backend) || "ollama";
	const hw = await detectHardware({ vram, ram });
	const plan = buildPlan(hw);
	if (args.includes("--json")) {
		console.log(planJson(plan, backend));
	} else {
		console.log(`${planSummary(plan, hw.source)}\n\n${rolesYaml(plan, { backend })}`);
	}
}
