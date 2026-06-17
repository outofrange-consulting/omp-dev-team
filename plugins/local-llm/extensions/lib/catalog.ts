// Model catalog for the OMP local-llm plugin.
// All sizes are Q4_K_M approximations for GGUF on llama.cpp/ollama — CALIBRATE
// against your own quant + KV-cache budget. tok/s notes assume a 16GB consumer
// card; MoE "min" = on-card portion when experts are offloaded (-ot exps=CPU).
// Quality is a relative agentic/coding score anchored to SWE-bench Verified
// (cited per-model in notes); refreshed June 2026 against ollama.com/library.

export type Role =
	| "default" | "task" | "smol" | "slow" | "commit" | "vision" | "code";

export type Arch = "dense" | "moe";

export interface ModelSpec {
	id: string; // provider-local model id (llama.cpp)
	name: string;
	arch: Arch;
	vramFullGB: number; // weights fully resident on GPU
	vramMinGB: number; // on-card portion when offloading (== vramFullGB for dense)
	ramOffloadGB: number; // extra system RAM consumed by offloaded experts (MoE)
	quality: number; // 0..100 relative agentic/coding quality
	roles: Role[]; // roles this model is eligible for
	reasoning: boolean;
	thinkingFormat?: "zai" | "qwen-chat-template" | "qwen" | "openai";
	contextWindow: number;
	input: ("text" | "image")[];
	pull: string; // `ollama pull` tag (also the ollama-served model id)
	hf?: string; // Hugging Face GGUF repo hint for llama.cpp
	note?: string;
}

// Ordered roughly by quality within tier. Edit freely — this IS the tier map.
export const CATALOG: ModelSpec[] = [
	{
		id: "qwen3.6-27b", name: "Qwen3.6-27B (dense)", arch: "dense",
		vramFullGB: 17, vramMinGB: 17, ramOffloadGB: 0, quality: 92,
		roles: ["slow", "task", "default", "vision"], reasoning: true,
		thinkingFormat: "qwen-chat-template", contextWindow: 262144,
		input: ["text", "image"], pull: "qwen3.6:27b",
		note: "★ Best quality in class: SWE-bench Verified ~77 (beats prior Qwen3.5-397B). Dense 17GB → oncard on 24GB, spills ~3.5GB to RAM on 16GB (slower). Multimodal (image+video). Apache-2.0.",
	},
	{
		id: "qwen3.6-35b-a3b", name: "Qwen3.6-35B-A3B (MoE)", arch: "moe",
		vramFullGB: 24, vramMinGB: 11, ramOffloadGB: 13, quality: 86,
		roles: ["slow", "task", "default", "vision"], reasoning: true,
		thinkingFormat: "qwen-chat-template", contextWindow: 262144,
		input: ["text", "image"], pull: "qwen3.6:35b-a3b",
		note: "SWE-bench Verified ~73; 3B active so fast under expert-offload on 16GB. Multimodal, Apache-2.0.",
	},
	{
		id: "devstral-small-2-24b", name: "Devstral-Small-2-24B", arch: "dense",
		vramFullGB: 15, vramMinGB: 15, ramOffloadGB: 0, quality: 82,
		roles: ["code", "task", "default", "vision"], reasoning: false, contextWindow: 262144,
		input: ["text", "image"], pull: "devstral-small-2:24b",
		note: "★ Best coding pick on 24GB: SWE-bench Verified ~68 (above larger generalists), Apache-2.0, 256K ctx, image input. Dense 24B → oncard on an RTX 4090/32GB Mac, spills on 16GB. Mistral tool-id/result quirks (set in emit compat).",
	},
	{
		id: "glm-4.7-flash", name: "GLM-4.7-Flash (30B-A3B)", arch: "moe",
		vramFullGB: 19, vramMinGB: 10, ramOffloadGB: 9, quality: 78,
		roles: ["task", "default", "slow"], reasoning: true,
		thinkingFormat: "zai", contextWindow: 198000,
		input: ["text"], pull: "glm-4.7-flash",
		note: "★ Primary agentic pick for 16GB: SWE-bench Verified ~59, 3B active → 60-80+ tok/s under offload. MIT. Watch chat-template quirks on older Ollama.",
	},
	{
		id: "qwen3-coder-30b", name: "Qwen3-Coder-30B-A3B", arch: "moe",
		vramFullGB: 19, vramMinGB: 10, ramOffloadGB: 9, quality: 68,
		roles: ["task", "code"], reasoning: false, contextWindow: 262144,
		input: ["text"], pull: "qwen3-coder:30b",
		note: "SWE-bench Verified ~52 (OpenHands). Non-thinking; fast tool calling on Ollama new engine. Apache-2.0.",
	},
	{
		id: "gpt-oss-20b", name: "GPT-OSS-20B", arch: "moe",
		vramFullGB: 13, vramMinGB: 8, ramOffloadGB: 6, quality: 55,
		roles: ["task", "default"], reasoning: true, thinkingFormat: "openai",
		contextWindow: 131072, input: ["text"], pull: "gpt-oss:20b",
		note: "SWE-bench Verified ~30 (harness-sensitive); VRAM-efficient fallback that leaves headroom for KV cache. Apache-2.0.",
	},
	{
		id: "qwen2.5-coder-14b", name: "Qwen2.5-Coder-14B", arch: "dense",
		vramFullGB: 9, vramMinGB: 9, ramOffloadGB: 0, quality: 48,
		roles: ["smol", "commit", "code", "default"], reasoning: false,
		contextWindow: 32768, input: ["text"], pull: "qwen2.5-coder:14b",
		note: "Tops its size tier for code completion/short tasks; cheap fit for smol/commit. Apache-2.0.",
	},
	{
		id: "ministral-3-14b", name: "Ministral-3-14B (vision)", arch: "dense",
		vramFullGB: 9, vramMinGB: 9, ramOffloadGB: 0, quality: 45,
		roles: ["vision", "smol"], reasoning: false, contextWindow: 32768,
		input: ["text", "image"], pull: "ministral-3:14b",
		note: "Cheap multimodal fallback when a bigger vision model won't fit.",
	},
	{
		id: "qwen2.5-coder-7b", name: "Qwen2.5-Coder-7B", arch: "dense",
		vramFullGB: 5, vramMinGB: 5, ramOffloadGB: 0, quality: 38,
		roles: ["smol", "commit"], reasoning: false, contextWindow: 32768,
		input: ["text"], pull: "qwen2.5-coder:7b",
		note: "Cheapest fast fit for commit messages / tiny edits.",
	},
];

// Harmless default export so OMP top-level discovery never treats lib/ as an entry.
export default function () {}
