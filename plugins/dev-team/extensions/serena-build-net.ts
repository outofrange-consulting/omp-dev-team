// serena-build-net.ts — build + test safety net after Serena C# edits.
//
// Port of the serena-forge Claude Code hooks `queue-build.sh` (PostToolUse on
// Serena's symbolic write tools) + `flush-build-queue.sh` (blocking Stop hook).
// During a turn we note the `.csproj` that owns each Serena-edited `.cs` file; at
// `session_stop` (the agent is about to finish) we compile the touched
// project(s) and, unless disabled, run the stack's tests. If either fails we
// BLOCK the stop and hand the errors back so the agent fixes them before the
// turn can end — a red build (or a failing test) is unfinished work.
//
// This is a HARD gate: OMP's `session_stop` hook may return
// `{ decision: "block", reason }` to prevent the agent stopping (the same
// mechanism Claude Code's Stop hook uses). To guarantee we never trap the user,
// a bounded fix counter (maxFixes, default 3) degrades to report-only once the
// budget is spent — and OMP itself caps consecutive continuations at 8.
//
// Opt-outs (env):
//   SERENA_FORGE_BUILD=0   disable the whole safety net (build + test gate)
//   SERENA_FORGE_TEST=0    build-gate only; do NOT run tests
// Per-repo overrides live in .omp/dev-team.json -> serenaBuildNet. This is kept
// SEPARATE from implVerify on purpose: this automatic gate must NOT inherit
// /impl-verify's strict `-warnaserror` default. Whether warnings are errors is
// the PROJECT's decision (TreatWarningsAsErrors in the .csproj /
// Directory.Build.props), so the default build here is a plain `dotnet build`
// that honours those settings. Override only if a team wants something else:
//   { "serenaBuildNet": { "maxFixes": 3,
//                         "build": "dotnet build",
//                         "test":  "dotnet test --nologo" } }
//
// FAIL-OPEN: a missing toolchain (no dotnet) or an internal error allows the
// stop — the net never traps a turn because of its own bug.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execSync } from "node:child_process";
import { existsSync, readdirSync } from "node:fs";
import { dirname, isAbsolute, join } from "node:path";
import { tail } from "./lib/impl-verify-core.ts";
import { readJSON, readState, writeState } from "./lib/shared.ts";

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
	for (let i = 0; i < 64 && dir && dir !== "/"; i++) {
		try {
			const proj = readdirSync(dir).find((f) => f.toLowerCase().endsWith(".csproj"));
			if (proj) return join(dir, proj);
		} catch {
			break;
		}
		if (dir === cwd) break;
		const parent = dirname(dir);
		if (parent === dir) break;
		dir = parent;
	}
	return null;
}

interface DevTeamConfig {
	// serena-build-net's own gate config — separate from implVerify so the
	// automatic gate does NOT force -warnaserror; warnings-as-errors is left to
	// the project's csproj / Directory.Build.props.
	serenaBuildNet?: { build?: string; test?: string; maxFixes?: number };
	implVerify?: { maxFixes?: number };
}

// Run a shell command; return {ok, output, timedOut, missing}. missing=true when
// the toolchain isn't installed (ENOENT) — we fail open on that.
function run(cmd: string, cwd: string): {
	ok: boolean;
	output: string;
	timedOut: boolean;
	missing: boolean;
} {
	try {
		const output = execSync(cmd, {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "pipe"],
			env: process.env,
			timeout: 15 * 60 * 1000, // 15 min hard cap so a hang can't wedge the stop
			maxBuffer: 32 * 1024 * 1024,
		});
		return { ok: true, output, timedOut: false, missing: false };
	} catch (err) {
		const e = err as {
			code?: string | number;
			signal?: string;
			stdout?: string;
			stderr?: string;
			message?: string;
		};
		const missing = e.code === "ENOENT";
		const timedOut = e.signal === "SIGTERM" || e.code === "ETIMEDOUT";
		const output = `${e.stdout ?? ""}${e.stderr ?? ""}` || e.message || "";
		return { ok: false, output, timedOut, missing };
	}
}

export default function serenaBuildNet(pi: ExtensionAPI) {
	pi.setLabel("serena-build-net");

	// Absolute .csproj paths touched by Serena edits during the session.
	let queue = new Set<string>();

	pi.on("session_start", async (_event, ctx) => {
		queue = new Set<string>();
		try {
			writeState(ctx.cwd, "serena-build.json", { attempts: 0 });
		} catch {
			/* best-effort */
		}
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

	// HARD gate: block the stop until the touched project(s) build and tests pass.
	pi.on("session_stop", async (_event, ctx) => {
		if (process.env.SERENA_FORGE_BUILD === "0") {
			queue = new Set<string>();
			return;
		}
		if (queue.size === 0) return; // no C# edits this session → nothing to gate
		const projects = [...queue].filter((p) => existsSync(p));
		if (projects.length === 0) {
			queue = new Set<string>();
			return;
		}

		const cfg = readJSON<DevTeamConfig>(join(ctx.cwd, ".omp", "dev-team.json"), {});
		const sbn = cfg.serenaBuildNet ?? {};
		const maxFixes = Math.max(1, sbn.maxFixes ?? cfg.implVerify?.maxFixes ?? 3);
		// Plain `dotnet build`: honour the project's own TreatWarningsAsErrors
		// (csproj / Directory.Build.props). We deliberately do NOT force
		// -warnaserror here — that belongs in the project, not in this gate.
		const buildCmd = sbn.build ?? "dotnet build";
		const testCmd = sbn.test ?? "dotnet test --nologo";
		const runTests = process.env.SERENA_FORGE_TEST !== "0";

		// --- build each touched project (scoped, fast; project decides warnings) ---
		const failures: string[] = [];
		for (const proj of projects) {
			const r = run(`${buildCmd} "${proj}" --no-restore --nologo`, ctx.cwd);
			if (r.missing) {
				queue = new Set<string>();
				return; // no dotnet → fail-open, allow stop
			}
			if (r.timedOut) {
				if (ctx.hasUI)
					ctx.ui.notify(`serena-forge: build of ${proj} timed out — skipping gate`, "warn");
				queue = new Set<string>();
				return; // don't wedge the stop on a slow/hung build
			}
			if (!r.ok) failures.push(`BUILD ${proj}\n${tail(r.output)}`);
		}

		// --- tests (whole configured suite), only if the build is clean ---
		let testFailure = "";
		if (failures.length === 0 && runTests) {
			const r = run(testCmd, ctx.cwd);
			if (r.missing) {
				queue = new Set<string>();
				return;
			}
			if (r.timedOut) {
				if (ctx.hasUI)
					ctx.ui.notify("serena-forge: tests timed out — skipping test gate", "warn");
			} else if (!r.ok) {
				testFailure = `TESTS ($ ${testCmd})\n${tail(r.output)}`;
			}
		}

		// --- verdict ---
		if (failures.length === 0 && !testFailure) {
			// Green: reset the counter, clear the queue, allow the stop.
			try {
				writeState(ctx.cwd, "serena-build.json", { attempts: 0 });
			} catch {
				/* best-effort */
			}
			queue = new Set<string>();
			if (ctx.hasUI)
				ctx.ui.notify(
					`serena-forge: ${projects.length} touched project(s) build${runTests ? " + tests" : ""} green ✓`,
					"info",
				);
			return; // allow stop
		}

		const detail = [...failures, testFailure].filter(Boolean).join("\n\n");
		const prev = readState<{ attempts: number }>(ctx.cwd, "serena-build.json", {
			attempts: 0,
		});
		const attempts = prev.attempts + 1;

		if (attempts >= maxFixes) {
			// Budget spent — report but DON'T trap the user. Reset and allow stop.
			try {
				writeState(ctx.cwd, "serena-build.json", { attempts: 0 });
			} catch {
				/* best-effort */
			}
			queue = new Set<string>();
			if (ctx.hasUI)
				ctx.ui.notify(
					`serena-forge: build/tests still failing after ${attempts}/${maxFixes} attempts — stopping anyway. Escalate:\n\n${detail}`,
					"warn",
				);
			return; // allow stop (HALT)
		}

		// Block the stop and feed the failure back so the agent fixes it.
		writeState(ctx.cwd, "serena-build.json", { attempts });
		return {
			decision: "block",
			reason:
				`serena-forge build/test gate FAILED after your C# edits (fix attempt ${attempts}/${maxFixes}). ` +
				`Do not finish with a red build or failing tests — fix the cause through Serena's symbolic tools, ` +
				`then let the turn end. Opt out only if the user asks (SERENA_FORGE_BUILD=0, or SERENA_FORGE_TEST=0 for build-only).\n\n${detail}`,
		};
	});
}
