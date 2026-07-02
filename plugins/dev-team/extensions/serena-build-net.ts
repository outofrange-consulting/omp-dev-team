// serena-build-net.ts — dotnet build safety net after Serena edits.
//
// Port of the serena-forge Claude Code hooks `queue-build.sh` (PostToolUse on
// Serena's symbolic write tools) + `flush-build-queue.sh` (Stop hook). During a
// turn we note the `.csproj` that owns each Serena-edited `.cs` file; at
// `turn_end` we compile the touched project(s) once with a scoped
// `dotnet build --no-restore` and surface any compiler errors.
//
// This is the compilation check the graph/symbol tools can't give you: after
// Serena mutates a symbol, the touched project is actually compiled by Roslyn's
// real build. Debounced to one build per turn (a full build after every symbolic
// edit is prohibitively slow on large solutions).
//
// FIDELITY NOTE: serena-forge's Stop hook can *block the stop* and force a fix
// loop. OMP's `turn_end` fires after the turn and cannot re-open it, so this port
// is REPORT-ONLY — it emits the compiler errors as a warning. Treat a red build
// as unfinished work and fix it (through Serena) on the next turn. For a hard
// gate, use /impl-verify.
//
// Opt-out: SERENA_FORGE_BUILD=0 disables the whole safety net.
// FAIL-OPEN: any internal error (no dotnet, no csproj, spawn failure) is a
// silent no-op — the safety net never breaks a turn because of its own bug.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";

// Serena's symbolic write tools. Matched by suffix so it works whether OMP
// exposes them bare (`replace_symbol_body`) or namespaced (`serena__…`,
// `mcp__serena__…`, `serena.…`).
const SERENA_EDIT_TOOLS = [
	"replace_symbol_body",
	"insert_after_symbol",
	"insert_before_symbol",
	"rename_symbol",
	"safe_delete_symbol",
	"replace_content",
	"replace_in_files",
	"create_text_file",
];

function isSerenaEdit(toolName: string): boolean {
	const tn = toolName.toLowerCase();
	return SERENA_EDIT_TOOLS.some((t) => tn === t || tn.endsWith(t));
}

function targetPath(input: Record<string, unknown>): string | null {
	for (const k of ["relative_path", "file_path", "path", "filePath"]) {
		const v = input[k];
		if (typeof v === "string" && v) return v;
	}
	return null;
}

function isCSharpFile(p: string): boolean {
	return /\.cs$/i.test(p.trim());
}

// Nearest .csproj walking up from the edited file's directory, bounded by cwd so
// we never escape the repo. Returns an absolute .csproj path or null.
function nearestCsproj(absFile: string, cwd: string): string | null {
	let dir = dirname(absFile);
	// Guard against an unbounded loop; a repo tree is never this deep.
	for (let i = 0; i < 64 && dir && dir !== "/"; i++) {
		try {
			const proj = readdirSync(dir).find((f) => f.toLowerCase().endsWith(".csproj"));
			if (proj) return join(dir, proj);
		} catch {
			/* unreadable dir — stop walking */
			break;
		}
		if (dir === cwd) break;
		const parent = dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return null;
}

export default function serenaBuildNet(pi: ExtensionAPI) {
	pi.setLabel("serena-build-net");

	// Absolute .csproj paths touched by Serena edits during the current turn.
	let queue = new Set<string>();

	pi.on("session_start", async () => {
		queue = new Set<string>();
	});

	// Enqueue on the way in (pre-run): we build the project targeted this turn.
	pi.on("tool_call", async (event, ctx) => {
		if (process.env.SERENA_FORGE_BUILD === "0") return;
		if (!isSerenaEdit(event.toolName)) return;
		const input = (event.input ?? {}) as Record<string, unknown>;
		const rel = targetPath(input);
		if (!rel || !isCSharpFile(rel)) return;
		const abs = isAbsolute(rel) ? rel : join(ctx.cwd, rel);
		const proj = nearestCsproj(abs, ctx.cwd);
		if (proj) queue.add(proj);
	});

	pi.on("turn_end", async (_event, ctx) => {
		if (process.env.SERENA_FORGE_BUILD === "0") {
			queue = new Set<string>();
			return;
		}
		if (queue.size === 0) return;
		const projects = [...queue];
		queue = new Set<string>();
		if (!ctx.hasUI) return; // nothing to surface without a UI

		const failures: string[] = [];
		for (const proj of projects) {
			if (!existsSync(proj)) continue;
			try {
				execFileSync(
					"dotnet",
					["build", proj, "--no-restore", "--nologo", "-clp:NoSummary"],
					{ cwd: ctx.cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
				);
				// exit 0 → compiled cleanly.
			} catch (e) {
				const err = e as { code?: string; stdout?: string; stderr?: string };
				if (err.code === "ENOENT") return; // dotnet not installed → fail-open, stop
				const out = `${err.stdout ?? ""}\n${err.stderr ?? ""}`;
				const errs = out
					.split("\n")
					.filter((l) => /error/i.test(l))
					.slice(0, 20)
					.join("\n");
				failures.push(`Project: ${proj}\n${errs || out.split("\n").slice(-20).join("\n")}`);
			}
		}
		if (failures.length === 0) return;
		ctx.ui.notify(
			`serena-forge build check FAILED after your C# edits — the touched project(s) do not compile. ` +
				`Fix these through Serena before finishing (a red build is unfinished work):\n\n` +
				`${failures.join("\n\n")}`,
			"warn",
		);
	});
}
