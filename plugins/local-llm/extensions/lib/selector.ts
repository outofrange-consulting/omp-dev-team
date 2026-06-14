// Pure selection logic: given hardware, classify each model's fit and assign
// the best one per role. No side effects — trivially unit-testable.

import { CATALOG, type ModelSpec, type Role } from "./catalog.ts";

export interface Hardware {
	vramGB: number;
	ramGB: number;
	/** Optional cap so offloaded experts never exceed this much system RAM. */
	maxRamBudgetGB?: number;
}

export type FitMode = "oncard" | "moe-offload" | "dense-spill" | "no-fit";

export interface Fit {
	model: ModelSpec;
	mode: FitMode;
	score: number; // quality * speed factor (0 if no-fit)
	detail: string;
}

// Tunables.
const VRAM_RESERVE_GB = 2.5; // KV cache + CUDA/OS overhead kept off the weights
const RAM_RESERVE_GB = 4; // leave headroom for the OS / your editor
const DENSE_SPILL_CAP_GB = 6; // max VRAM a dense model may overflow before "no-fit"
const SPEED_FACTOR: Record<Exclude<FitMode, "no-fit">, number> = {
	oncard: 1.0,
	"moe-offload": 0.9, // active params are tiny, RAM bandwidth barely felt
	"dense-spill": 0.55, // dense layers crossing PCIe hurt a lot
};

export function classify(model: ModelSpec, hw: Hardware): Fit {
	const usableVram = hw.vramGB - VRAM_RESERVE_GB;
	const ramBudget = Math.min(hw.ramGB - RAM_RESERVE_GB, hw.maxRamBudgetGB ?? Infinity);

	if (model.vramFullGB <= usableVram) {
		return mk(model, "oncard", `weights ${model.vramFullGB}GB ≤ ${usableVram.toFixed(1)}GB usable VRAM`);
	}
	if (model.arch === "moe" && model.vramMinGB <= usableVram && model.ramOffloadGB <= ramBudget) {
		return mk(model, "moe-offload",
			`on-card ${model.vramMinGB}GB + ${model.ramOffloadGB}GB experts in RAM (budget ${fmt(ramBudget)}GB)`);
	}
	if (model.arch === "dense") {
		const spill = model.vramFullGB - usableVram;
		if (spill <= DENSE_SPILL_CAP_GB && spill <= ramBudget) {
			return mk(model, "dense-spill", `spills ${spill.toFixed(1)}GB of layers to RAM`);
		}
	}
	return { model, mode: "no-fit", score: 0, detail: `needs ${model.vramFullGB}GB VRAM (have ${usableVram.toFixed(1)}GB usable)` };
}

function mk(model: ModelSpec, mode: Exclude<FitMode, "no-fit">, detail: string): Fit {
	return { model, mode, score: model.quality * SPEED_FACTOR[mode], detail };
}
function fmt(n: number) {
	return n === Infinity ? "∞" : n.toFixed(0);
}

export interface Plan {
	hardware: Hardware;
	/** Models that fit at all, best score first — these get registered. */
	available: Fit[];
	/** role -> chosen model id (provider-local id). */
	roles: Partial<Record<Role, string>>;
	rationale: string[];
}

const ROLE_ORDER: Role[] = ["task", "default", "smol", "commit", "slow", "vision", "code"];

export function buildPlan(hw: Hardware): Plan {
	const fits = CATALOG.map((m) => classify(m, hw))
		.filter((f) => f.mode !== "no-fit")
		.sort((a, b) => b.score - a.score);

	const roles: Partial<Record<Role, string>> = {};
	const rationale: string[] = [];

	for (const role of ROLE_ORDER) {
		const pool = fits.filter((f) => f.model.roles.includes(role));
		if (pool.length === 0) continue;
		let pick: Fit;
		if (role === "smol" || role === "commit") {
			// smol/commit want the cheapest fast fit, not the highest quality.
			pick = [...pool].sort((a, b) => a.model.vramFullGB - b.model.vramFullGB)[0];
		} else {
			pick = pool[0];
		}
		roles[role] = pick.model.id;
		rationale.push(`${role.padEnd(8)} → ${pick.model.name}  [${pick.mode}] (${pick.detail})`);
	}
	return { hardware: hw, available: fits, roles, rationale };
}

export default function () {}
