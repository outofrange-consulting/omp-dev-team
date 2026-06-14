// Model catalog for the OMP local-llm plugin.
// All sizes are Q4_K_M approximations for GGUF on llama.cpp/ollama — CALIBRATE
// against your own quant + KV-cache budget. tok/s notes assume a 16GB consumer
// card; MoE "min" = on-card portion when experts are offloaded (-ot exps=CPU).

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
		vramFullGB: 18, vramMinGB: 18, ramOffloadGB: 0, quality: 88,
		roles: ["slow", "task", "default"], reasoning: true,
		thinkingFormat: "qwen-chat-template", contextWindow: 262144,
		input: ["text"], pull: "qwen3.6:27b",
		note: "Best quality in class; dense => spills to RAM on 16GB (slower). Prefer bartowski IQ3 quant.",
	},
	{
		id: "glm-4.7-flash", name: "GLM-4.7-Flash (30B-A3B)", arch: "moe",
		vramFullGB: 16, vramMinGB: 9, ramOffloadGB: 9, quality: 85,
		roles: ["task", "default", "slow"], reasoning: true,
		thinkingFormat: "zai", contextWindow: 131072,
		input: ["text"], pull: "glm-4.7-flash",
		note: "★ Primary agentic pick for 16GB: SWE-bench Verified ~59, 60-80+ tok/s.",
	},
	{
		id: "qwen3.6-35b-a3b", name: "Qwen3.6-35B-A3B (MoE)", arch: "moe",
		vramFullGB: 21, vramMinGB: 11, ramOffloadGB: 12, quality: 80,
		roles: ["slow", "task"], reasoning: true,
		thinkingFormat: "qwen-chat-template", contextWindow: 262144,
		input: ["text"], pull: "qwen3.6:35b-a3b",
	},
	{
		id: "qwen3-coder-30b-a3b", name: "Qwen3-Coder-30B-A3B", arch: "moe",
		vramFullGB: 17, vramMinGB: 9, ramOffloadGB: 10, quality: 70,
		roles: ["task", "code"], reasoning: false, contextWindow: 262144,
		input: ["text"], pull: "qwen3-coder:30b-a3b",
		note: "Non-thinking; fast tool calling on Ollama new engine.",
	},
	{
		id: "devstral-2-24b", name: "Devstral-2-Small-24B", arch: "dense",
		vramFullGB: 15, vramMinGB: 15, ramOffloadGB: 0, quality: 68,
		roles: ["code", "task"], reasoning: false, contextWindow: 131072,
		input: ["text"], pull: "devstral-2:24b",
		note: "Mistral tool-id/result quirks (set in emit compat).",
	},
	{
		id: "gpt-oss-20b", name: "GPT-OSS-20B", arch: "moe",
		vramFullGB: 13, vramMinGB: 8, ramOffloadGB: 6, quality: 62,
		roles: ["task", "default"], reasoning: true, thinkingFormat: "openai",
		contextWindow: 131072, input: ["text"], pull: "gpt-oss:20b",
		note: "VRAM-efficient fallback; leaves headroom for KV cache.",
	},
	{
		id: "qwen2.5-coder-14b", name: "Qwen2.5-Coder-14B", arch: "dense",
		vramFullGB: 9, vramMinGB: 9, ramOffloadGB: 0, quality: 55,
		roles: ["smol", "commit", "code", "default"], reasoning: false,
		contextWindow: 32768, input: ["text"], pull: "qwen2.5-coder:14b",
	},
	{
		id: "ministral-3-14b", name: "Ministral-3-14B (vision)", arch: "dense",
		vramFullGB: 9, vramMinGB: 9, ramOffloadGB: 0, quality: 50,
		roles: ["vision", "smol"], reasoning: false, contextWindow: 32768,
		input: ["text", "image"], pull: "ministral-3:14b",
	},
	{
		id: "qwen2.5-coder-7b", name: "Qwen2.5-Coder-7B", arch: "dense",
		vramFullGB: 5, vramMinGB: 5, ramOffloadGB: 0, quality: 42,
		roles: ["smol", "commit"], reasoning: false, contextWindow: 32768,
		input: ["text"], pull: "qwen2.5-coder:7b",
	},
];

// Harmless default export so OMP top-level discovery never treats lib/ as an entry.
export default function () {}
