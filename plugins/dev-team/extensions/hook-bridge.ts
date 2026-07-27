// hook-bridge.ts — run upstream agentic-dev-team's Python hooks unmodified.
//
// WHY THIS EXISTS
// Upstream registers ~38 hook invocations in `hooks/hooks.json` as Claude Code
// `type: "command"` entries. OMP has no command hooks at all: `--hook` is an
// alias for `--extension` and the loader expects a JS/TS factory (see OMP
// docs/hooks.md). A faithful port therefore had exactly two options — rewrite 31
// Python hooks plus their 25 shared libs in TypeScript, or translate the event
// contract once. This is the translation.
//
// The Python is copied byte-for-byte from upstream. Everything this file does is
// protocol conversion, so an upstream bump is `git pull` in the clone plus a
// re-run of scripts/port-upstream-dev-team.mjs.
//
// THE CONTRACT WE HONOUR (docs/python-hook-contract.md upstream)
//   stdin      one JSON blob: session_id, hook_event_name, cwd, tool_name,
//              tool_input, tool_response, transcript_path, prompt
//   stdout     USER-VISIBLE. "[BLOCK]" prefix on a block body, "ADVISORY:" on an
//              advisory line, empty for a silent pass.
//   exit code  0 pass · 1 advisory · 2 BLOCK · >=3 hook-specific
//
// Exit 2 is the only code that stops a tool call, and it maps onto OMP's
// `{ block: true, reason }` result. Everything else surfaces as a notification,
// which matches upstream's "stdout is UI, not logging" rule.
//
// FAIL-OPEN, DELIBERATELY. A hook that crashes, times out, or cannot find a
// Python interpreter must not wedge the session: it is logged and the tool call
// proceeds. The one exception is a hook that explicitly exits 2 — that is a
// decision, not a failure. This mirrors upstream, whose own hooks are written to
// "silently pass when a field they need is missing rather than crashing".

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

/** The plugin root, derived from this file's location (extensions/ -> ..). */
const PLUGIN_ROOT = resolve(dirname(new URL(import.meta.url).pathname), "..");
const HOOKS_DIR = join(PLUGIN_ROOT, "hooks");
const MANIFEST = join(HOOKS_DIR, "omp-hooks.json");
const PY_SH = join(HOOKS_DIR, "py.sh");

/** Per-hook wall-clock budget. Upstream hooks are meant to be fast; a runaway
 *  one must not hold a tool call open. */
const TIMEOUT_MS = Number(process.env.DEV_TEAM_HOOK_TIMEOUT_MS ?? 15_000);

type Manifest = Record<string, { matcher?: string; scripts: string[] }[]>;

/** OMP tool name -> the Claude Code name upstream's matchers are written against.
 *  Upstream matchers are regexes like "Write|Edit" or "Agent|Task". */
const TOOL_NAME_TO_UPSTREAM: Record<string, string> = {
	read: "Read",
	write: "Write",
	edit: "Edit",
	grep: "Grep",
	glob: "Glob",
	bash: "Bash",
	task: "Agent",
	todo: "TodoWrite",
	web_search: "WebSearch",
	ask: "AskUserQuestion",
};

interface HookOutcome {
	block: boolean;
	message: string;
}

function loadManifest(): Manifest {
	try {
		return JSON.parse(readFileSync(MANIFEST, "utf8")) as Manifest;
	} catch {
		return {};
	}
}

/** Run one Python hook against the upstream stdin/stdout/exit-code contract. */
function runHook(script: string, payload: unknown): HookOutcome {
	const path = join(HOOKS_DIR, script);
	if (!existsSync(path)) return { block: false, message: "" };
	try {
		// py.sh resolves a working Python 3 across python3 / py -3 / python, which
		// is why it ships as .sh — it runs before an interpreter is guaranteed.
		const stdout = execFileSync("sh", [PY_SH, path], {
			input: JSON.stringify(payload),
			encoding: "utf8",
			timeout: TIMEOUT_MS,
			cwd: String((payload as { cwd?: string }).cwd ?? process.cwd()),
			env: { ...process.env, PYTHONIOENCODING: "utf-8", DEV_TEAM_ROOT: PLUGIN_ROOT },
			maxBuffer: 1 << 22,
		});
		return { block: false, message: stdout.trim() };
	} catch (e) {
		const err = e as { status?: number; stdout?: string; stderr?: string; code?: string };
		const out = (err.stdout ?? "").toString().trim();
		// Exit 2 is upstream's block signal — the ONLY failure we honour.
		if (err.status === 2) return { block: true, message: out || `${script} blocked this call` };
		// Exit 1 is advisory: surface it, do not block.
		if (err.status === 1) return { block: false, message: out };
		// Anything else (crash, timeout, missing interpreter) fails open.
		const why = err.code === "ETIMEDOUT" ? `timed out after ${TIMEOUT_MS}ms` : (err.stderr ?? "").toString().trim();
		return { block: false, message: why ? `dev-team hook ${script}: ${why} (ignored)` : "" };
	}
}

/** Run every hook registered for an event, honouring upstream's matcher regex. */
function dispatch(
	manifest: Manifest,
	event: string,
	toolName: string | undefined,
	payload: Record<string, unknown>,
): HookOutcome {
	const groups = manifest[event] ?? [];
	const messages: string[] = [];
	for (const group of groups) {
		if (group.matcher && group.matcher !== "*") {
			const upstreamName = toolName ? (TOOL_NAME_TO_UPSTREAM[toolName] ?? toolName) : "";
			// Anchored: upstream writes "Write|Edit", meaning the WHOLE name.
			if (!new RegExp(`^(?:${group.matcher})$`).test(upstreamName)) continue;
		}
		for (const script of group.scripts) {
			const r = runHook(script, { ...payload, hook_event_name: event });
			if (r.message) messages.push(r.message);
			// First block wins — stop running the rest, exactly as a halted tool
			// call would in Claude Code.
			if (r.block) return { block: true, message: messages.join("\n") };
		}
	}
	return { block: false, message: messages.join("\n") };
}

export default function hookBridge(pi: ExtensionAPI): void {
	pi.setLabel("dev-team hooks");

	const manifest = loadManifest();
	if (Object.keys(manifest).length === 0) return;

	// One probe at load time: without a Python 3 the whole layer is inert, and a
	// silently inert guard layer is precisely the failure upstream hit for months
	// (ADR 0011's amendment). Say so once, loudly, instead of per tool call.
	let pythonOk = true;
	try {
		execFileSync("sh", [PY_SH, "-c", ""], { timeout: TIMEOUT_MS, stdio: "ignore" });
	} catch (e) {
		if ((e as { status?: number }).status === 2) pythonOk = false;
	}

	pi.on("session_start", async (_event, ctx) => {
		if (!pythonOk) {
			ctx.ui.notify(
				"dev-team: no Python 3 found — the hook layer (guards, gates, telemetry) is INERT. " +
					"Install Python 3.8+ or set DEV_TEAM_PYTHON.",
				"error",
			);
			return;
		}
		const r = dispatch(manifest, "SessionStart", undefined, { cwd: ctx.cwd });
		if (r.message) ctx.ui.notify(r.message, "info");
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!pythonOk) return;
		const r = dispatch(manifest, "PreToolUse", event.toolName, {
			cwd: ctx.cwd,
			tool_name: TOOL_NAME_TO_UPSTREAM[event.toolName] ?? event.toolName,
			tool_input: event.input,
		});
		if (r.block) return { block: true, reason: r.message };
		if (r.message) ctx.ui.notify(r.message, "warning");
		return;
	});

	pi.on("tool_result", async (event, ctx) => {
		if (!pythonOk) return;
		// Upstream's post hooks read `tool_response` as {exitCode, stdout, stderr}.
		// OMP models a result as content blocks + isError + a per-tool `details`,
		// so rebuild the shape upstream parses rather than handing it a foreign one.
		const text = event.content
			.map((c) => (c.type === "text" ? c.text : ""))
			.join("")
			.trim();
		const r = dispatch(manifest, "PostToolUse", event.toolName, {
			cwd: ctx.cwd,
			tool_name: TOOL_NAME_TO_UPSTREAM[event.toolName] ?? event.toolName,
			tool_input: event.input,
			tool_response: {
				exitCode: event.isError ? 1 : 0,
				stdout: event.isError ? "" : text,
				stderr: event.isError ? text : "",
			},
		});
		// PostToolUse cannot block — the call already ran. Upstream's post hooks
		// are formatters and reviewers; their output is advisory by construction.
		if (r.message) ctx.ui.notify(r.message, "warning");
		return;
	});

	pi.on("input", async (event, ctx) => {
		if (!pythonOk) return;
		const r = dispatch(manifest, "UserPromptSubmit", undefined, {
			cwd: ctx.cwd,
			prompt: (event as { text?: string }).text ?? "",
		});
		if (r.message) ctx.ui.notify(r.message, "info");
		return;
	});

	pi.on("session_stop", async (_event, ctx) => {
		if (!pythonOk) return;
		const r = dispatch(manifest, "Stop", undefined, { cwd: ctx.cwd });
		if (r.message) ctx.ui.notify(r.message, "info");
	});

	pi.on("agent_end", async (_event, ctx) => {
		if (!pythonOk) return;
		const r = dispatch(manifest, "SubagentStop", undefined, { cwd: ctx.cwd });
		if (r.message) ctx.ui.notify(r.message, "info");
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (!pythonOk) return;
		dispatch(manifest, "SessionEnd", undefined, { cwd: ctx.cwd });
	});
}
