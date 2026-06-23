// impl-verify.ts — /impl-verify: a deterministic build+test gate for the
// implement loop. Ported (in spirit) from cde-dotnetcc's impl-build.js: the
// mechanical decisions — which command to run per stack, pass/fail, and the
// bounded fix counter — live in CODE here, so the agent reads a one-line verdict
// instead of running build, reading full logs, running test, reading full logs,
// and counting attempts itself. Strict builds (e.g. dotnet -warnaserror) make
// the no-disable-analyzers rule enforced by the toolchain, not by the model.
//
// Usage (run by software-engineer/qa-engineer after each implemented unit):
//   /impl-verify                 detect stack, run strict build + tests
//   /impl-verify --skip-tests    build only (e.g. mid-RED)
//   /impl-verify --stack dotnet  force a stack
//   /impl-verify --reset         clear the fix counter
//
// Stack + budget overrides live in the project's .omp/dev-team.json:
//   { "implVerify": { "maxFixes": 3,
//                     "stacks": { "node": { "build": "...", "test": "..." } } } }

import { execSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
	DEFAULT_STACKS,
	type Stack,
	type StackCommands,
	type VerifyState,
	computeVerdict,
	detectStack,
	tail,
} from "./lib/impl-verify-core.ts";
import { readJSON, readState, writeState } from "./lib/shared.ts";

interface ImplVerifyConfig {
	maxFixes?: number;
	stacks?: Partial<Record<Stack, Partial<StackCommands>>>;
}

function loadConfig(cwd: string): ImplVerifyConfig {
	const cfg = readJSON<{ implVerify?: ImplVerifyConfig }>(
		join(cwd, ".omp", "dev-team.json"),
		{},
	);
	return cfg.implVerify ?? {};
}

function repoFiles(cwd: string): string[] {
	try {
		return readdirSync(cwd);
	} catch {
		return [];
	}
}

// Run a command; return whether it exited 0 and its combined output.
function run(cmd: string, cwd: string): { ok: boolean; output: string } {
	try {
		const output = execSync(cmd, {
			cwd,
			encoding: "utf8",
			stdio: ["ignore", "pipe", "pipe"],
			env: process.env,
		});
		return { ok: true, output };
	} catch (err) {
		const e = err as { stdout?: string; stderr?: string; message?: string };
		const output = `${e.stdout ?? ""}${e.stderr ?? ""}` || e.message || "";
		return { ok: false, output };
	}
}

interface Flags {
	skipTests: boolean;
	reset: boolean;
	stack?: Stack;
	maxFixes?: number;
}

function parseFlags(args: string): Flags {
	const toks = (args ?? "").trim().split(/\s+/).filter(Boolean);
	const f: Flags = { skipTests: false, reset: false };
	for (let i = 0; i < toks.length; i++) {
		const t = toks[i];
		if (t === "--skip-tests") f.skipTests = true;
		else if (t === "--reset") f.reset = true;
		else if (t === "--stack") f.stack = toks[++i] as Stack;
		else if (t.startsWith("--stack=")) f.stack = t.slice(8) as Stack;
		else if (t === "--max-fixes") f.maxFixes = Number(toks[++i]);
		else if (t.startsWith("--max-fixes=")) f.maxFixes = Number(t.slice(12));
	}
	return f;
}

export default function implVerify(pi: ExtensionAPI) {
	pi.setLabel("impl-verify");

	pi.registerCommand("impl-verify", {
		description:
			"Deterministic build+test gate: run the stack's strict build (+ tests) and return a bounded PASS/FAIL/HALT verdict",
		handler: async (args, ctx) => {
			const flags = parseFlags(String(args ?? ""));
			const cwd = ctx.cwd;

			if (flags.reset) {
				writeState(cwd, "impl-verify.json", { attempts: 0 } satisfies VerifyState);
				ctx.ui.notify("impl-verify: fix counter reset", "info");
				return "impl-verify: fix counter reset.";
			}

			const cfg = loadConfig(cwd);
			const stack = flags.stack ?? detectStack(repoFiles(cwd));
			if (!stack) {
				const msg =
					"impl-verify: could not detect a stack (no .csproj/.sln, package.json, pyproject.toml, go.mod, Cargo.toml). Pass --stack <name> or add it to .omp/dev-team.json.";
				ctx.ui.notify(msg, "warn");
				return msg;
			}

			const cmds: StackCommands = {
				...DEFAULT_STACKS[stack],
				...(cfg.stacks?.[stack] ?? {}),
			};
			const maxFixes = flags.maxFixes ?? cfg.maxFixes ?? 3;

			const build = run(cmds.build, cwd);
			const test = build.ok && !flags.skipTests ? run(cmds.test, cwd) : null;
			const testOk = flags.skipTests ? true : (test?.ok ?? false);

			const prev = readState<VerifyState>(cwd, "impl-verify.json", { attempts: 0 });
			const verdict = computeVerdict({
				prev,
				buildOk: build.ok,
				testOk,
				skipTests: flags.skipTests,
				maxFixes,
			});
			writeState(cwd, "impl-verify.json", verdict.state);

			let report = `impl-verify [${stack}] ${verdict.line}`;
			if (verdict.status !== "PASS") {
				const failing = !build.ok ? build : test;
				const t = failing ? tail(failing.output) : "";
				const failedCmd = !build.ok ? cmds.build : cmds.test;
				report += `\n$ ${failedCmd}\n${t}`;
			}
			ctx.ui.notify(report, verdict.status === "PASS" ? "info" : "warn");
			return report;
		},
	});
}
