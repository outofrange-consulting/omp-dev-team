#!/usr/bin/env node
// dt — the dev-team gate CLI for GitHub Copilot CLI.
//
// Copilot CLI has no user-defined slash commands, so the OMP dev-team commands
// (/scope, /plan-approve, /freeze, /review-approve, /careful, ...) become this
// tiny out-of-tree state CLI. The preToolUse hook (pre-tool-use.mjs) reads the
// same state and enforces the gate. Run it from inside the repo you're working in.
//
//   dt scope [--trivial|--complex]   pre-analysis: classify the task size
//   dt trivial                       shortcut for `dt scope --trivial`
//   dt plan-approve [planPath]       approve the plan -> unlock source edits
//   dt approve                       alias for plan-approve
//   dt reset | plan-reset            re-arm the gate (next task must scope again)
//   dt status                        show the current gate/freeze/careful state
//   dt freeze <glob...>              lock path glob(s) against edits
//   dt unfreeze <glob...|all>        unlock path glob(s)
//   dt review-approve                record the staged set as review-approved
//   dt careful on|off                toggle careful mode (block destructive cmds)
//   dt allow-feature-edits           allow editing .feature specs this repo
//   dt protect-features              re-protect .feature specs
//   dt init [dir]                    arm the guards in a repo: write .github/hooks
//                                    + .github/copilot-instructions.md
//   dt help

import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { readState, writeState, nowISO } from "./hooks/scripts/common.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const cwd = process.cwd();
const [cmd, ...args] = process.argv.slice(2);

const C = { dim: "\x1b[2m", b: "\x1b[1m", y: "\x1b[33m", g: "\x1b[32m", r: "\x1b[0m" };
const log = (m) => process.stdout.write(`${m}\n`);
const ok = (m) => log(`${C.g}ok${C.r} ${m}`);
const warn = (m) => log(`${C.y}! ${m}${C.r}`);

function setPlan(stage, size, planPath) {
	writeState(cwd, "plan-gate.json", { stage, size, planPath, at: nowISO() });
}

switch ((cmd || "help").toLowerCase()) {
	case "scope": {
		if (args.includes("--trivial")) {
			setPlan("trivial", "trivial");
			warn("scoped TRIVIAL — source edits unlocked. `dt reset` to re-arm.");
		} else {
			const size = args.includes("--complex") ? "complex" : "standard";
			setPlan("needs-plan", size);
			log(`scoped NON-TRIVIAL (${size}) — plan it, get human sign-off, then \`dt plan-approve\`.`);
		}
		break;
	}
	case "trivial":
		setPlan("trivial", "trivial");
		warn("scoped TRIVIAL — source edits unlocked. `dt reset` to re-arm.");
		break;
	case "plan-approve":
	case "approve": {
		const st = readState(cwd, "plan-gate.json", {});
		if (st.stage === undefined) {
			warn("run `dt scope` first — a plan can't be approved before the task is scoped.");
			break;
		}
		const planPath = args[0] || st.planPath;
		setPlan("plan-approved", st.size ?? "standard", planPath);
		ok(`plan approved${planPath ? ` (${planPath})` : ""} — implementation unlocked.`);
		break;
	}
	case "reset":
	case "plan-reset":
		writeState(cwd, "plan-gate.json", {});
		warn("plan gate re-armed — next source edit requires `dt scope` then (if non-trivial) `dt plan-approve`.");
		break;
	case "freeze": {
		const globs = args.filter(Boolean);
		const state = readState(cwd, "freeze.json", { globs: [] });
		if (globs.length === 0) {
			log(state.globs.length ? `frozen: ${state.globs.join(", ")}` : "nothing frozen");
			break;
		}
		state.globs = [...new Set([...state.globs, ...globs])];
		writeState(cwd, "freeze.json", state);
		warn(`frozen: ${state.globs.join(", ")}`);
		break;
	}
	case "unfreeze": {
		if (args.length === 0 || args[0] === "all") {
			writeState(cwd, "freeze.json", { globs: [] });
			ok("unfroze all");
			break;
		}
		const state = readState(cwd, "freeze.json", { globs: [] });
		const drop = new Set(args);
		state.globs = state.globs.filter((g) => !drop.has(g));
		writeState(cwd, "freeze.json", state);
		log(`frozen: ${state.globs.join(", ") || "(none)"}`);
		break;
	}
	case "review-approve": {
		const staged = stagedHash();
		if (!staged) {
			warn("nothing staged to approve");
			break;
		}
		writeState(cwd, "review-gate.json", { approvedHash: staged.hash, approvedAt: nowISO() });
		ok(`review approved for ${staged.files.length} staged file(s) — commit unlocked.`);
		break;
	}
	case "careful": {
		const on = (args[0] || "").toLowerCase() === "on";
		writeState(cwd, "careful.json", { active: on });
		on
			? warn("careful mode ON — destructive shell commands are blocked.")
			: ok("careful mode OFF.");
		break;
	}
	case "allow-feature-edits":
		writeState(cwd, "spec-guard.json", { allow: true });
		warn(".feature edits ALLOWED for this repo — change specs deliberately. `dt protect-features` to re-protect.");
		break;
	case "protect-features":
		writeState(cwd, "spec-guard.json", { allow: false });
		ok(".feature specs protected again (edits blocked).");
		break;
	case "status":
		status();
		break;
	case "init":
		init(args[0] ? resolve(args[0]) : cwd);
		break;
	default:
		help();
}

function status() {
	const pg = readState(cwd, "plan-gate.json", {});
	const fz = readState(cwd, "freeze.json", { globs: [] });
	const cf = readState(cwd, "careful.json", { active: false });
	const sg = readState(cwd, "spec-guard.json", { allow: false });
	const rg = readState(cwd, "review-gate.json", {});
	log(`${C.b}dev-team gate state${C.r}  (repo: ${repoRoot()})`);
	log(`  plan-gate : ${pg.stage ?? "needs-scope"}${pg.size ? ` (${pg.size})` : ""}`);
	log(`  freeze    : ${fz.globs.length ? fz.globs.join(", ") : "(none)"}`);
	log(`  careful   : ${cf.active ? "ON (destructive cmds blocked)" : "off"}`);
	log(`  features  : ${sg.allow ? "editable" : "protected"}`);
	log(`  review    : ${rg.approvedHash ? `approved ${rg.approvedAt}` : "not approved"}`);
}

// Arm the guards in a repo: write a project hooks file pointing at the absolute
// hook script, plus the dev-team copilot-instructions, so Copilot CLI loads them.
function init(dir) {
	const ghDir = join(dir, ".github");
	const hooksDir = join(ghDir, "hooks");
	mkdirSync(hooksDir, { recursive: true });
	const script = join(HERE, "hooks", "scripts", "pre-tool-use.mjs").replace(/\\/g, "/");
	const hooks = {
		version: 1,
		disableAllHooks: false,
		hooks: {
			preToolUse: [{ type: "command", command: `node "${script}"`, timeoutSec: 15 }],
		},
	};
	const hooksFile = join(hooksDir, "dev-team.json");
	writeFileSync(hooksFile, `${JSON.stringify(hooks, null, 2)}\n`, "utf8");
	ok(`wrote ${rel(dir, hooksFile)} (preToolUse guard)`);

	// If the token-diet pack is installed alongside dev-team (same global install),
	// also arm its postToolUse output-compression hook in this repo.
	const tdScript = join(HERE, "..", "token-diet", "hooks", "scripts", "post-tool-use.mjs");
	if (existsSync(tdScript)) {
		const tdHooks = {
			version: 1,
			disableAllHooks: false,
			hooks: {
				postToolUse: [
					{ type: "command", command: `node "${tdScript.replace(/\\/g, "/")}"`, timeoutSec: 15 },
				],
			},
		};
		const tdFile = join(hooksDir, "token-diet.json");
		writeFileSync(tdFile, `${JSON.stringify(tdHooks, null, 2)}\n`, "utf8");
		ok(`wrote ${rel(dir, tdFile)} (postToolUse output compression)`);
	}

	// copilot-instructions: append the dev-team block if not already present.
	const instSrc = join(HERE, "instructions", "copilot-instructions.md");
	const instDst = join(ghDir, "copilot-instructions.md");
	const marker = "<!-- dev-team:begin -->";
	const block = existsSync(instSrc) ? readFileSync(instSrc, "utf8") : "";
	const existing = existsSync(instDst) ? readFileSync(instDst, "utf8") : "";
	if (block && !existing.includes(marker)) {
		writeFileSync(instDst, existing ? `${existing.trimEnd()}\n\n${block}` : block, "utf8");
		ok(`wrote ${rel(dir, instDst)} (dev-team operating manual)`);
	} else if (existing.includes(marker)) {
		log(`  ${rel(dir, instDst)} already has the dev-team block — left as is.`);
	}
	log("");
	log(`Guards armed. The agentic flow: scope -> plan -> build -> review -> pr.`);
	log(`Next: \`dt scope\` (or \`dt scope --trivial\`), then drive Copilot CLI with`);
	log(`\`/agent specs\`, \`/agent plan\`, \`/agent build\`, \`/agent review\`, \`/agent pr\`.`);
}

function repoRoot() {
	try {
		return execSync("git rev-parse --show-toplevel", { cwd, encoding: "utf8" }).trim() || cwd;
	} catch {
		return cwd;
	}
}
function rel(base, p) {
	return p.startsWith(base) ? p.slice(base.length).replace(/^[/\\]/, "") : p;
}
function stagedHash() {
	try {
		const files = execSync("git diff --cached --name-only", { cwd, encoding: "utf8" })
			.split("\n")
			.map((s) => s.trim())
			.filter(Boolean);
		if (files.length === 0) return null;
		const diff = execSync("git diff --cached", { cwd, encoding: "utf8" });
		return { hash: createHash("sha256").update(diff).digest("hex").slice(0, 16), files };
	} catch {
		return null;
	}
}

function help() {
	const src = readFileSync(fileURLToPath(import.meta.url), "utf8");
	// Only the leading comment block (stop at the first non-comment line).
	const header = [];
	for (const l of src.split("\n")) {
		if (l.startsWith("#!")) continue;
		if (!l.startsWith("//")) break;
		header.push(l.replace(/^\/\/ ?/, ""));
	}
	const start = header.findIndex((l) => l.trimStart().startsWith("dt scope"));
	log(`${C.b}dt — dev-team gate CLI for GitHub Copilot CLI${C.r}\n`);
	log(`${C.b}Commands${C.r}`);
	log(header.slice(start >= 0 ? start : 0).join("\n"));
}
