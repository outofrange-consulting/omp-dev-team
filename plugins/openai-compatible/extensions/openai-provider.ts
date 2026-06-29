// openai-provider — register any OpenAI-compatible endpoint (LiteLLM, Ollama,
// vLLM, LocalAI, …) as a named provider in OMP.
//
// Any service that implements:
//   GET  /v1/models               -> { data: ModelInfo[] }
//   POST /v1/chat/completions      -> standard OpenAI chat response
//   Authorization: Bearer <key>   (optional)
// is supported.
//
// This extension:
//   • provides a CLI (used by install.sh/ps1) that probes the endpoint, lists
//     its models, and emits the ~/.omp/agent/models.yml provider block.
//   • registers a `/oai-provider` command to re-list models at runtime.
//   • when OAI_PROVIDER_URL (+ OAI_PROVIDER_NAME) is set, registers the
//     provider live on startup.
//
// Security: the API key is NEVER read from an environment variable at runtime.
// install.sh/ps1 store it in ~/.omp/<name>.key (chmod 600) and reference it
// from models.yml via `apiKey: "!cat …"`. The extension reads the file
// directly when it needs the key for live re-registration.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const DEFAULT_PROVIDER_NAME = "litellm";

// Normalise a user-supplied URL to the OpenAI base (".../v1"). Accepts
// "http://host:4000", "http://host:4000/", or "http://host:4000/v1".
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
		const j = await r.json() as unknown;
		if (
			j !== null &&
			typeof j === "object" &&
			"data" in j &&
			Array.isArray((j as { data: unknown }).data)
		) {
			return (j as { data: ModelInfo[] }).data;
		}
		return [];
	} finally {
		clearTimeout(t);
	}
}

// The provider block for ~/.omp/agent/models.yml. `discovery: openai-models-list`
// keeps the model list fresh at runtime; we don't pin a stale catalogue.
export function providerYaml(name: string, baseUrl: string, apiKeyRef: string): string {
	return [
		"providers:",
		`  ${name}:`,
		`    baseUrl: ${baseUrl}`,
		`    api: openai-completions`,
		`    apiKey: ${apiKeyRef}`,
		"    authHeader: true",
		"    discovery:",
		"      type: openai-models-list",
	].join("\n");
}

// Live registration config (static models.yml is the source of truth; this
// only fires at startup when OAI_PROVIDER_URL is set and re-registration is
// requested via /oai-provider).
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

// Read the API key from the key file, if present. Never reads from env.
function readKeyFile(name: string): string {
	try {
		return readFileSync(join(homedir(), ".omp", `${name}.key`), "utf8").trim();
	} catch {
		return "";
	}
}

async function registerLive(pi: ExtensionAPI, name: string, base: string): Promise<string> {
	if (!("registerProvider" in pi) || typeof pi.registerProvider !== "function") {
		return `${name}: registerProvider not available in this OMP version`;
	}
	const key = readKeyFile(name);
	try {
		const models = await listModels(base, key);
		// registerProvider is verified to exist and be a function above; the cast
		// narrows to the concrete call signature since ExtensionAPI omits it.
		const reg = pi.registerProvider as (n: string, c: unknown) => void;
		reg(name, providerConfig(base, key, models));
		return `${name}: registered ${models.length} model(s) from ${base}`;
	} catch (e) {
		return `${name}: could not reach ${base} (${(e as Error).message})`;
	}
}

export default function openaiProvider(pi: ExtensionAPI) {
	const name = process.env.OAI_PROVIDER_NAME ?? DEFAULT_PROVIDER_NAME;
	const rawUrl = process.env.OAI_PROVIDER_URL;
	pi.setLabel(`openai-compatible(${name})`);

	if (rawUrl) {
		const base = normalizeBaseUrl(rawUrl);
		void registerLive(pi, name, base).catch(() => {});
	}

	pi.registerCommand("oai-provider", {
		description:
			"List models from the configured OpenAI-compatible provider and (re)register it",
		handler: async (_args, ctx) => {
			const url = process.env.OAI_PROVIDER_URL;
			const providerName = process.env.OAI_PROVIDER_NAME ?? DEFAULT_PROVIDER_NAME;
			if (!url) {
				ctx.ui.notify(
					"OAI_PROVIDER_URL is not set. Run plugins/openai-compatible/install.sh to configure it.",
					"warn",
				);
				return;
			}
			const base = normalizeBaseUrl(url);
			const msg = await registerLive(pi, providerName, base);
			ctx.ui.notify(msg, "info");
		},
	});
}

// ---- Standalone CLI (used by install.sh/ps1) -------------------------------
// bun openai-provider.ts --list --url <u> [--api-key <k>]
//   -> one model id per line
// bun openai-provider.ts --yaml --name <n> --url <u> [--api-key-ref <ref>]
//   -> the models.yml block
if (import.meta.main) {
	const args = process.argv.slice(2);
	const arg = (k: string): string | undefined => {
		const i = args.indexOf(k);
		return i >= 0 ? args[i + 1] : undefined;
	};
	const url = arg("--url");
	if (!url) {
		console.error(
			"usage: openai-provider.ts --list|--yaml --url <endpoint> [--name <n>] [--api-key <k> | --api-key-ref <ref>]",
		);
		process.exit(2);
	}
	const base = normalizeBaseUrl(url);
	if (args.includes("--yaml")) {
		const name = arg("--name") ?? DEFAULT_PROVIDER_NAME;
		console.log(providerYaml(name, base, arg("--api-key-ref") ?? '""'));
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
