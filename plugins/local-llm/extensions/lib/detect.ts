// Hardware detection for the local-llm plugin. Best-effort, cross-platform,
// no deps. RAM via os.totalmem(); VRAM via nvidia-smi / rocm-smi / Apple unified
// memory. Override with OMP_LOCAL_VRAM_GB / OMP_LOCAL_RAM_GB (or args).

import { execSync } from "node:child_process";
import os from "node:os";

export interface Hardware {
	vramGB: number;
	ramGB: number;
	source: string;
	gpu?: string;
}

function sh(cmd: string): string {
	try {
		return execSync(cmd, { stdio: ["ignore", "pipe", "ignore"], encoding: "utf8" }).trim();
	} catch {
		return "";
	}
}

export async function detectHardware(over: { vram?: number; ram?: number } = {}): Promise<Hardware> {
	const ramGB = over.ram ?? (process.env.OMP_LOCAL_RAM_GB ? Number(process.env.OMP_LOCAL_RAM_GB) : Math.round(os.totalmem() / 1e9));
	const vramOverride = over.vram ?? (process.env.OMP_LOCAL_VRAM_GB ? Number(process.env.OMP_LOCAL_VRAM_GB) : undefined);
	if (vramOverride != null && !Number.isNaN(vramOverride)) {
		return { vramGB: vramOverride, ramGB, source: "override", gpu: "override" };
	}

	// NVIDIA (Linux / Windows / WSL) — pick the largest GPU.
	const smi = sh("nvidia-smi --query-gpu=memory.total,name --format=csv,noheader,nounits");
	if (smi) {
		const best = smi
			.split("\n")
			.map((l) => l.split(","))
			.map((r) => ({ mib: Number((r[0] ?? "").trim()) || 0, name: (r[1] ?? "").trim() }))
			.sort((a, b) => b.mib - a.mib)[0];
		if (best?.mib) return { vramGB: Math.round(best.mib / 1024), ramGB, source: "nvidia-smi", gpu: best.name };
	}

	// Apple Silicon — unified memory; the GPU can use most of system RAM.
	if (process.platform === "darwin" && sh("uname -m") === "arm64") {
		const chip = sh("sysctl -n machdep.cpu.brand_string") || "Apple Silicon";
		return { vramGB: Math.floor(ramGB * 0.7), ramGB, source: "apple-unified", gpu: chip };
	}

	// AMD ROCm.
	const rocm = sh("rocm-smi --showmeminfo vram --csv");
	if (rocm) {
		const m = rocm.match(/(\d{8,})/); // total VRAM in bytes
		if (m) return { vramGB: Math.round(Number(m[1]) / 1e9), ramGB, source: "rocm-smi", gpu: "AMD" };
	}

	return { vramGB: vramOverride ?? 0, ramGB, source: "unknown", gpu: undefined };
}

export default function () {}
