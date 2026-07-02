// serena-enforce.ts — force symbolic C# work through Serena.
//
// Port of the serena-forge Claude Code hooks `enforce-serena-write.sh` (write
// block) and `prefer-symbolic-read.sh` (read nudge) to a single OMP extension.
//
//   WRITE (hard):  writes to `*.cs` via `write`/`edit`/`astEdit` (and the obvious
//                  shell write paths) are DENIED and redirected to Serena's
//                  Roslyn-backed symbolic edit tools (replace_symbol_body,
//                  insert_after_symbol, rename_symbol, safe_delete_symbol, …).
//   READ (nudge):  a whole-file read of a `.cs` file over a line threshold asks
//                  for confirmation (interactive) or warns (headless), steering
//                  to get_symbols_overview → find_symbol → include_body. Bounded
//                  reads (offset/limit set) and small files pass through. Reads
//                  are NEVER hard-denied — that would only teach the agent to
//                  route around the guard.
//
// Scope is GLOBAL by design: `.cs` writes are blocked in every repo once the
// plugin is active, with intentionally NO built-in bypass. If Serena genuinely
// cannot make an edit, the agent is told to STOP and ask the user to fix Serena
// or disable this extension — never to work around the block. The messages are
// onboarding-aware: in a repo with no `.serena/` folder they steer the agent to
// propose onboarding (the serena-setup skill) rather than fall back to a native
// edit.
//
// FAIL-OPEN ON OWN MALFUNCTION: like the other dev-team guards, any internal
// error just lets the tool call through. The only path that ever BLOCKS is the
// explicit, well-formed `.cs` write deny (or an explicit user-declined read).
//
// Tunables (env):
//   SERENA_FORGE_READ_MAXLINES  read-nudge line threshold (default 100; 0 = off)

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { bashWriteTargets, pathsFromToolInput } from "./lib/shared.ts";

// Ends in ".cs" (case-insensitive) — but NOT .csproj / .cshtml / .csx / .css,
// none of which END in ".cs". Mirrors serena-forge's `*.[cC][sS]` glob.
function isCSharpFile(p: string): boolean {
	return /\.cs$/i.test(p.trim());
}

// astEdit isn't covered by shared.ts's pathsFromToolInput; pull its target from
// the common field names so a symbol/AST edit to a .cs file is caught too. Any
// miss just fails open (no block).
function astEditPaths(input: Record<string, unknown>): string[] {
	const out: string[] = [];
	for (const key of ["path", "file", "filePath", "file_path", "target"]) {
		const v = input[key];
		if (typeof v === "string" && v) out.push(v);
	}
	return out;
}

function isOnboarded(cwd: string): boolean {
	try {
		return existsSync(join(cwd, ".serena"));
	} catch {
		return false;
	}
}

// Steer the agent to Serena's symbolic edit tools; onboarding-aware.
function writeDenyReason(path: string, cwd: string): string {
	const head = `Editing C# (.cs) via write/edit/astEdit is blocked by serena-forge (target: ${path}).`;
	if (isOnboarded(cwd)) {
		return (
			`${head} Change this file through Serena's symbolic tools instead: survey it with ` +
			`get_symbols_overview, locate the target with find_symbol, then edit with ` +
			`replace_symbol_body, insert_after_symbol, insert_before_symbol (or rename_symbol / ` +
			`safe_delete_symbol for structural changes). If you cannot make the change through ` +
			`Serena — the language server is unavailable, timed out, the project targets .NET 9 ` +
			`(Serena's Roslyn backend is .NET 10-only), or the edit cannot be expressed symbolically ` +
			`— STOP and ask the user to fix Serena or disable the serena-enforce extension. Do not ` +
			`work around this block.`
		);
	}
	return (
		`${head} This repo is NOT Serena-onboarded yet (no .serena/ folder), so Serena's symbolic ` +
		`edit tools cannot act on it. PROPOSE to the user that you onboard this repo now with the ` +
		`serena-setup skill (it activates and indexes the project), and run it once they agree — ` +
		`then make the change through Serena's symbolic tools. Do NOT work around this block with a ` +
		`native .cs write.`
	);
}

function readNudgeReason(path: string, lines: number, max: number): string {
	return (
		`This is a whole-file read of a ${lines}-line C# file (serena-forge prefers symbolic reads ` +
		`over ~${max} lines). Prefer Serena: get_symbols_overview on ${path} to map its symbols, ` +
		`then find_symbol (include_body: true) on just the target symbol, and find_referencing_symbols ` +
		`instead of grep for impact. If you genuinely need raw lines, read a bounded slice (set limit/` +
		`offset) rather than the whole file.`
	);
}

const BOUNDED_KEYS = ["offset", "limit", "range", "lineRange", "start", "end"];
function isBoundedRead(input: Record<string, unknown>): boolean {
	return BOUNDED_KEYS.some((k) => input[k] !== undefined && input[k] !== null);
}

function countLines(cwd: string, path: string): number | null {
	try {
		const abs = isAbsolute(path) ? path : join(cwd, path);
		if (!existsSync(abs)) return null;
		const text = readFileSync(abs, "utf8");
		if (text.length === 0) return 0;
		let n = 1;
		for (let i = 0; i < text.length; i++) if (text.charCodeAt(i) === 10) n++;
		return n;
	} catch {
		return null;
	}
}

export default function serenaEnforce(pi: ExtensionAPI) {
	pi.setLabel("serena-enforce");

	// Advisory once-per-session onboarding-status signal (mirrors the serena-forge
	// SessionStart banner's onboarding line). The Serena-first *protocol* is carried
	// by the C#-scoped rule rules/serena-first.md; this is just the dynamic hint.
	let announced = false;
	pi.on("session_start", async (_event, ctx) => {
		if (announced) return;
		announced = true;
		if (!ctx.hasUI) return;
		try {
			ctx.ui.notify(
				isOnboarded(ctx.cwd)
					? "serena-forge active — .cs writes go through Serena's symbolic tools; whole-file .cs reads are nudged toward symbolic reads. This repo is Serena-onboarded (.serena/ present)."
					: "serena-forge active — .cs writes go through Serena's symbolic tools. This repo is NOT onboarded yet; propose /skill:serena-setup before editing C# here.",
				"info",
			);
		} catch {
			/* advisory only — never break a session */
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		const input = (event.input ?? {}) as Record<string, unknown>;

		// ---- READ nudge (never a hard deny) --------------------------------
		if (event.toolName === "read") {
			const max = Number.parseInt(
				process.env.SERENA_FORGE_READ_MAXLINES ?? "100",
				10,
			);
			if (!Number.isFinite(max) || max <= 0) return; // disabled
			const path = typeof input.path === "string" ? input.path : "";
			if (!path || !isCSharpFile(path)) return;
			if (isBoundedRead(input)) return; // already a slice
			const lines = countLines(ctx.cwd, path);
			if (lines === null || lines <= max) return; // small/unknown → pass

			const confirm = (ctx.ui as { confirm?: unknown }).confirm;
			if (ctx.hasUI && typeof confirm === "function") {
				try {
					const ok = await (
						confirm as (t: string, m: string) => Promise<boolean>
					).call(
						ctx.ui,
						"serena-forge",
						`Whole-file read of a ${lines}-line C# file. Prefer Serena symbolic reads (get_symbols_overview → find_symbol). Read the whole file anyway?`,
					);
					if (ok === false) {
						return { block: true, reason: readNudgeReason(path, lines, max) };
					}
				} catch {
					/* confirm unavailable/failed → fall through to advisory */
				}
				return; // confirmed (or confirm errored) → allow
			}
			// Headless / no confirm primitive: advisory nudge, do not block.
			if (ctx.hasUI) ctx.ui.notify(readNudgeReason(path, lines, max), "warn");
			return;
		}

		// ---- WRITE block (hard deny) ---------------------------------------
		// write / edit — reliable path extraction via shared helper.
		if (event.toolName === "write" || event.toolName === "edit") {
			for (const p of pathsFromToolInput(event.toolName, input)) {
				if (isCSharpFile(p))
					return { block: true, reason: writeDenyReason(p, ctx.cwd) };
			}
			return;
		}

		// astEdit — best-effort field extraction (native AST editor).
		if (event.toolName === "astEdit") {
			for (const p of astEditPaths(input)) {
				if (isCSharpFile(p))
					return { block: true, reason: writeDenyReason(p, ctx.cwd) };
			}
			return;
		}

		// bash (best-effort): catch .cs writes performed via the shell — redirection,
		// tee, sed -i, cp/mv dest — so the write block can't be trivially bypassed
		// with `cat > Foo.cs`. Consistent with how path-guard/freeze-guard extend to
		// the shell. Process-driven writes (dotnet new / scaffolding) pass through.
		if (event.toolName === "bash") {
			const cmd = String(input.command ?? "");
			if (!cmd) return;
			for (const p of bashWriteTargets(cmd)) {
				if (isCSharpFile(p))
					return { block: true, reason: writeDenyReason(p, ctx.cwd) };
			}
			return;
		}
	});
}
