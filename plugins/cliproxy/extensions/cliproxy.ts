// cliproxy — register a CLIProxyAPI gateway (https://github.com/router-for-me/
// CLIProxyAPI) as an OpenAI-compatible model provider in OMP.
//
// CLIProxyAPI exposes upstream models (Gemini/Codex/Claude/Grok via CLI accounts)
// behind a standard OpenAI API: `GET /v1/models` lists them, `POST /v1/chat/
// completions` runs them, both authenticated with `Authorization: Bearer <key>`.
//
// This extension:
//   • provides a CLI (used by install.sh/ps1) that probes a gateway, lists its
//     models, and emits the `~/.omp/agent/models.yml` provider block.
//   • registers a `/cliproxy` command to re-list models at runtime.
//   • when CLIPROXY_URL (+ CLIPROXY_API_KEY) is set, registers the provider live.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export const PROVIDER = "cliproxy";

// Normalise a user-supplied URL to the OpenAI base (".../v1"). Accepts
// "http://host:8317", "http://host:8317/", or "http://host:8317/v1".
export function normalizeBaseUrl(input: string): string {
	let u = input.trim().replace(/\/+$/, "");
	if (!/^https?:\/\//.test(u)) u = `http://${u}`;
	if (!/\/v1$/.test(u)) u = `${u}/v1`;
	return u;
}

export interface ModelInfo {
	id: string;
	owned_by?: string;
}

export async function listModels(baseUrl: string, apiKey: string): Promise<ModelInfo[]> {
	const headers: Record<string, string> = { Accept: "application/json" };
	if (apiKey) headers.Authorization = `Bearer ${apiKey}`;
	const c = new AbortController();
	const t = setTimeout(() => c.abort(), 8000);
	try {
		const r = await fetch(`${baseUrl}/models`, { headers, signal: c.signal });
		if (!r.ok) throw new Error(`HTTP ${r.status} from ${baseUrl}/models`);
		const j = (await r.json()) as { data?: ModelInfo[] };
		return Array.isArray(j.data) ? j.data : [];
	} finally {
		clearTimeout(t);
	}
}

// The provider block for ~/.omp/agent/models.yml. `discovery: openai-models-list`
// keeps the model list fresh at runtime, so we don't pin a stale catalogue.
export function providerYaml(baseUrl: string, apiKeyRef: string): string {
	return [
		"providers:",
		`  ${PROVIDER}:`,
		`    baseUrl: ${baseUrl}`,
		`    api: openai-completions`,
		`    apiKey: ${apiKeyRef}`,
		"    authHeader: true",
		"    discovery:",
		"      type: openai-models-list",
	].join("\n");
}

// Live registration (optional — the static models.yml is the source of truth).
export function providerConfig(baseUrl: string, apiKey: string, models: ModelInfo[]) {
	return {
		baseUrl,
		api: "openai-completions",
		auth: apiKey ? "apiKey" : "none",
		apiKey,
		authHeader: true,
		models: models.map((m) => ({
			id: m.id,
			name: m.id,
			contextWindow: 128000,
			maxTokens: 16384,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
		})),
	};
}

async function registerLive(pi: ExtensionAPI): Promise<string | null> {
	const url = process.env.CLIPROXY_URL;
	const key = process.env.CLIPROXY_API_KEY ?? "";
	if (!url) return null;
	const base = normalizeBaseUrl(url);
	try {
		const models = await listModels(base, key);
		(pi as unknown as { registerProvider?: (n: string, c: unknown) => void }).registerProvider?.(
			PROVIDER,
			providerConfig(base, key, models),
		);
		return `cliproxy: registered ${models.length} model(s) from ${base}`;
	} catch (e) {
		return `cliproxy: could not reach ${base} (${(e as Error).message})`;
	}
}

export default function cliproxy(pi: ExtensionAPI) {
	pi.setLabel("cliproxy");
	void registerLive(pi).catch(() => {});
	pi.registerCommand("cliproxy", {
		description: "List models from the configured CLIProxyAPI gateway and (re)register the provider",
		handler: async (_args, ctx) => {
			const url = process.env.CLIPROXY_URL;
			if (!url) {
				ctx.ui.notify("CLIPROXY_URL is not set. Run plugins/cliproxy/install.sh to configure it.", "warn");
				return;
			}
			const msg = (await registerLive(pi)) ?? "cliproxy: nothing to do";
			ctx.ui.notify(msg, "info");
		},
	});
}

// ---- Standalone CLI (used by install.sh/ps1) -------------------------------
// bun cliproxy.ts --list --url <u> --api-key <k>     -> one model id per line
// bun cliproxy.ts --yaml --url <u> --api-key-ref <r> -> the models.yml block
if (import.meta.main) {
	const args = process.argv.slice(2);
	const arg = (k: string) => {
		const i = args.indexOf(k);
		return i >= 0 ? args[i + 1] : undefined;
	};
	const url = arg("--url");
	if (!url) {
		console.error("usage: cliproxy.ts --list|--yaml --url <gateway-url> [--api-key <k> | --api-key-ref <ref>]");
		process.exit(2);
	}
	const base = normalizeBaseUrl(url);
	if (args.includes("--yaml")) {
		console.log(providerYaml(base, arg("--api-key-ref") ?? '""'));
		process.exit(0);
	}
	// default / --list: probe and print model ids (exit non-zero if unreachable)
	try {
		const models = await listModels(base, arg("--api-key") ?? "");
		for (const m of models) console.log(m.id);
		process.exit(0);
	} catch (e) {
		console.error((e as Error).message);
		process.exit(1);
	}
}
