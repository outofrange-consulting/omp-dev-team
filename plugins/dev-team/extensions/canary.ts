// canary.ts — L4 "context loaded" verification for the dev-team plugin.
//
// The operating manual (rules/dev-team-operating-manual.md) is an `alwaysApply`
// rule: OMP splices its body into the system prompt of every context (main agent
// and every subagent). If that rule goes missing, gets renamed, or its
// `alwaysApply: true` frontmatter breaks, the whole dev-team behavioral contract
// silently fails to load — the classic "it stopped following the rules and nobody
// noticed" failure. This canary surfaces that at session start, not twenty
// minutes in.
//
// What it proves (honestly): the operating-manual rule shipped in the *installed*
// package (plugin cache under ~/.omp/plugins/cache) is present, still alwaysApply,
// and still carries the sentinel. OMP stages only extensions/ + package.json into
// ~/.omp/agent/extensions/dev-team/ — the full package (including rules/) lives in
// the plugin cache resolved via installed_plugins.json. CI check E in
// ci-framework-compliance.mjs covers the *source* file; this covers the *installed
// copy* at runtime. Belt and braces.

import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { appendJSONL, nowISO, statePath } from "./lib/shared.ts";

// Sentinel — MUST stay byte-identical in rules/dev-team-operating-manual.md and
// in scripts/ci-framework-compliance.mjs (check E enforces all three agree).
const CANARY_TOKEN = "DT-CANARY-7Q2F";

// OMP stages only extensions/ + package.json into the agent dir; the full package
// (including rules/) lives in the plugin cache.  Walk up from the staging root to
// <omp_data> and consult installed_plugins.json for the authoritative installPath.
const STAGING_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");

function resolveRulePath(): string {
	// Fast path: full package was staged (local dev or future OMP behaviour).
	const staged = join(STAGING_ROOT, "rules", "dev-team-operating-manual.md");
	if (existsSync(staged)) return staged;

	// STAGING_ROOT = <omp_data>/agent/extensions/dev-team → ../../.. = <omp_data>
	const ompData = resolve(STAGING_ROOT, "../../..");

	// Consult installed_plugins.json for the exact installPath.
	const installedJson = join(ompData, "plugins", "installed_plugins.json");
	if (existsSync(installedJson)) {
		try {
			const db = JSON.parse(readFileSync(installedJson, "utf8")) as {
				plugins?: Record<string, Array<{ installPath: string }>>;
			};
			const entries = db.plugins?.["dev-team@omp-dev-team"];
			if (entries?.length) {
				const installPath = entries[entries.length - 1].installPath;
				return join(installPath, "rules", "dev-team-operating-manual.md");
			}
		} catch {
			/* fall through */
		}
	}

	// Last resort: glob the cache dir for any dev-team package.
	const cacheDir = join(ompData, "plugins", "cache", "plugins");
	if (existsSync(cacheDir)) {
		const dirs = readdirSync(cacheDir).filter((d) =>
			d.startsWith("omp-dev-team___dev-team___"),
		);
		if (dirs.length) {
			dirs.sort();
			return join(cacheDir, dirs[dirs.length - 1], "rules", "dev-team-operating-manual.md");
		}
	}

	// No cache found — return the staged path so checkCanary emits "not found".
	return staged;
}

const RULE_PATH = resolveRulePath();

interface CanaryResult {
	ok: boolean;
	reason: string;
}

function checkCanary(): CanaryResult {
	if (!existsSync(RULE_PATH)) {
		return { ok: false, reason: "operating-manual rule not found in the loaded package" };
	}
	let text: string;
	try {
		text = readFileSync(RULE_PATH, "utf8");
	} catch (e) {
		return { ok: false, reason: `cannot read operating-manual rule: ${String(e)}` };
	}
	const fm = /^---\n([\s\S]*?)\n---/.exec(text);
	if (!fm || !/^\s*alwaysApply:\s*true\s*$/m.test(fm[1])) {
		return {
			ok: false,
			reason: "operating-manual is not `alwaysApply: true` — it will not load into context",
		};
	}
	if (!text.includes(CANARY_TOKEN)) {
		return {
			ok: false,
			reason: `operating-manual is missing canary sentinel ${CANARY_TOKEN} (stale or tampered copy)`,
		};
	}
	return { ok: true, reason: `operating-manual loaded (alwaysApply, ${CANARY_TOKEN})` };
}

export default function canary(pi: ExtensionAPI) {
	pi.setLabel("canary");

	let reported = false;

	// `manual` distinguishes the on-demand /canary run (always echoes) from the
	// automatic session-start run (only speaks up on failure, to stay quiet).
	const emit = (
		cwd: string,
		hasUI: boolean,
		notify: (m: string, t?: "info" | "warning" | "error") => void,
		manual: boolean,
	): void => {
		const res = checkCanary();
		try {
			appendJSONL(statePath(cwd, "canary.jsonl"), {
				ts: nowISO(),
				ok: res.ok,
				reason: res.reason,
				manual,
			});
		} catch {
			/* logging is best-effort; never let it break a session */
		}
		if (hasUI && (!res.ok || manual)) {
			notify(
				res.ok ? `canary OK — ${res.reason}` : `CANARY FAIL — ${res.reason}`,
				res.ok ? "info" : "warning",
			);
		}
	};

	pi.on("session_start", async (_event, ctx) => {
		if (reported) return; // once per session
		reported = true;
		emit(ctx.cwd, ctx.hasUI, (m, t) => ctx.ui.notify(m, t), false);
	});

	pi.registerCommand("canary", {
		description: "Verify the dev-team operating-manual rule loaded intact (L4 context canary)",
		handler: async (_args, ctx) => {
			emit(ctx.cwd, ctx.hasUI, (m, t) => ctx.ui.notify(m, t), true);
		},
	});
}
