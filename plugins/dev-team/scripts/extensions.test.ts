// Unit tests for dev-team's pure extension logic.
//   bun plugins/dev-team/scripts/extensions.test.ts
// No OMP dependency — exercises the quality-critical invariants directly:
// the /impl-verify stack detection + bounded verdict, and the path-matching
// case-insensitivity the secret/freeze guards rely on.

import {
	computeVerdict,
	detectStack,
	tail,
	type VerifyState,
} from "../extensions/lib/impl-verify-core.ts";
import { effectiveBand, globToRegExp, matchesAny } from "../extensions/lib/shared.ts";
import { gateDecision, isGatedSource } from "../extensions/plan-gate.ts";

// Workload-shaped 4-rung ladder: nano (lexical/scan) + code (coding/tool-use)
// split the cheap end. sizeBand starts at `code` (cheapest impl-capable band);
// `nano` is a workload-shape tier, only reached as a floor or via downshift.
const BAND = {
	ladder: ["nano", "code", "balanced", "deep"],
	sizeBand: { trivial: "code", standard: "balanced", complex: "deep" },
	bumpStages: ["needs-plan"],
};
// Opt-in trivial downshift (one band below floor on the fast path).
const BAND_DS = { ...BAND, trivialDownshift: true, downshiftStages: ["trivial"], protectDownshift: ["deep"] };

let failures = 0;
function check(name: string, cond: boolean, extra?: unknown): void {
	if (cond) {
		console.log(`  ok  ${name}`);
	} else {
		failures++;
		console.error(`FAIL  ${name}`, extra ?? "");
	}
}

// --- detectStack ----------------------------------------------------------
check("detectStack: dotnet from .csproj", detectStack(["Api.csproj", "README.md"]) === "dotnet");
check("detectStack: dotnet from .sln", detectStack(["App.sln"]) === "dotnet");
check("detectStack: node from package.json", detectStack(["package.json"]) === "node");
check("detectStack: python from pyproject", detectStack(["pyproject.toml"]) === "python");
check("detectStack: go from go.mod", detectStack(["go.mod"]) === "go");
check("detectStack: rust from Cargo.toml", detectStack(["Cargo.toml"]) === "rust");
// dotnet wins a mixed monorepo (the strict build most often skipped by hand).
check(
	"detectStack: dotnet wins over node in a mixed repo",
	detectStack(["package.json", "Api.csproj"]) === "dotnet",
);
check("detectStack: null when no markers", detectStack(["LICENSE", "notes.txt"]) === null);

// --- computeVerdict (bounded fix loop) ------------------------------------
const fresh: VerifyState = { attempts: 0 };

const pass = computeVerdict({ prev: { attempts: 2 }, buildOk: true, testOk: true, skipTests: false, maxFixes: 3 });
check("verdict: PASS on green", pass.status === "PASS");
check("verdict: PASS resets the counter", pass.state.attempts === 0);

const skip = computeVerdict({ prev: fresh, buildOk: true, testOk: false, skipTests: true, maxFixes: 3 });
check("verdict: PASS when tests skipped and build green", skip.status === "PASS");

const fail1 = computeVerdict({ prev: fresh, buildOk: false, testOk: false, skipTests: false, maxFixes: 3 });
check("verdict: FAIL on build break", fail1.status === "FAIL");
check("verdict: FAIL increments counter (1)", fail1.state.attempts === 1);
check("verdict: FAIL names build", fail1.line.includes("build"));

const fail2 = computeVerdict({ prev: fail1.state, buildOk: true, testOk: false, skipTests: false, maxFixes: 3 });
check("verdict: FAIL on test break", fail2.status === "FAIL" && fail2.state.attempts === 2);
check("verdict: FAIL names tests when build ok but tests red", fail2.line.includes("tests"));

const halt = computeVerdict({ prev: fail2.state, buildOk: false, testOk: false, skipTests: false, maxFixes: 3 });
check("verdict: HALT at the fix budget", halt.status === "HALT" && halt.state.attempts === 3);
check("verdict: HALT tells the agent to escalate", /escalate/i.test(halt.line));

const halt1 = computeVerdict({ prev: fresh, buildOk: false, testOk: false, skipTests: false, maxFixes: 1 });
check("verdict: HALT immediately when maxFixes=1", halt1.status === "HALT");

// --- tail -----------------------------------------------------------------
check("tail: keeps last N non-empty lines", tail("a\n\nb\n\n\nc\nd", 2) === "c\nd");

// --- globToRegExp / matchesAny (case-insensitive secret/freeze matching) --
check("glob: id_rsa matches uppercase ID_RSA", globToRegExp("id_rsa").test("ID_RSA"));
check("glob: *.pem matches .PEM", globToRegExp("*.pem").test("server.PEM"));
check("glob: *secret* matches mixed-case Secret", globToRegExp("*secret*").test("AppSecret.txt"));
check("glob: *.env does not match unrelated", !globToRegExp("*.key").test("main.ts"));
check("glob: ** spans directories", globToRegExp("**/id_rsa").test("home/user/.ssh/id_rsa"));
check(
	"matchesAny: returns the matching glob",
	matchesAny("config/app.key", ["*.pem", "*.key"]) === "*.key",
);
check("matchesAny: null when nothing matches", matchesAny("main.ts", ["*.pem", "*.key"]) === null);

// --- plan-gate: what counts as gated source -------------------------------
check("plan-gate: .ts source is gated", isGatedSource("src/app/main.ts"));
check("plan-gate: .cs source is gated", isGatedSource("Api/Service.cs"));
check("plan-gate: test file is NOT gated", !isGatedSource("src/app/main.test.ts"));
check("plan-gate: __tests__ path is NOT gated", !isGatedSource("src/__tests__/x.ts"));
check("plan-gate: .feature spec is NOT gated", !isGatedSource("features/login.feature"));
check("plan-gate: markdown doc is NOT gated", !isGatedSource("README.md"));
check("plan-gate: json config is NOT gated", !isGatedSource("package.json"));

// --- plan-gate: stage -> decision -----------------------------------------
check("plan-gate: undefined stage -> need-scope", gateDecision(undefined) === "need-scope");
check("plan-gate: needs-plan -> need-plan", gateDecision("needs-plan") === "need-plan");
check("plan-gate: trivial -> allow", gateDecision("trivial") === "allow");
check("plan-gate: plan-approved -> allow", gateDecision("plan-approved") === "allow");

// --- effort-band model routing (phase-aware bump-from-floor) -------------
// During planning (needs-plan): effective = max(floor, sizeBand[size]).
check("band: planning, nano floor, complex -> deep", effectiveBand("nano", "complex", "needs-plan", BAND) === "deep");
check("band: planning, nano floor, standard -> balanced", effectiveBand("nano", "standard", "needs-plan", BAND) === "balanced");
check("band: planning, nano floor, trivial -> code", effectiveBand("nano", "trivial", "needs-plan", BAND) === "code");
check("band: planning, code floor, trivial -> code (floor binds)", effectiveBand("code", "trivial", "needs-plan", BAND) === "code");
check("band: planning, code floor, complex -> deep", effectiveBand("code", "complex", "needs-plan", BAND) === "deep");
check("band: planning never below floor (balanced/trivial)", effectiveBand("balanced", "trivial", "needs-plan", BAND) === "balanced");
check("band: planning, deep floor holds", effectiveBand("deep", "standard", "needs-plan", BAND) === "deep");
// Build (plan-approved): NO bump — everyone at floor (a solid plan makes the build routine).
check("band: build, nano floor, complex -> nano (no bump)", effectiveBand("nano", "complex", "plan-approved", BAND) === "nano");
check("band: build, code floor, complex -> code (no bump)", effectiveBand("code", "complex", "plan-approved", BAND) === "code");
check("band: build, balanced floor, complex -> balanced (no bump)", effectiveBand("balanced", "complex", "plan-approved", BAND) === "balanced");
// Trivial stage / unscoped: no bump -> floor.
check("band: trivial stage -> floor", effectiveBand("nano", "complex", "trivial", BAND) === "nano");
check("band: unscoped (no stage) -> floor", effectiveBand("balanced", "complex", undefined, BAND) === "balanced");
// Off-ladder + no config.
check("band: off-ladder floor (pinned) unchanged", effectiveBand("pinned", "complex", "needs-plan", BAND) === "pinned");
check("band: no config -> floor", effectiveBand("nano", "complex", "needs-plan", undefined) === "nano");
// Opt-in trivial downshift: one band below floor on trivial, deep protected.
check("ds: balanced floor, trivial -> code (one below)", effectiveBand("balanced", "trivial", "trivial", BAND_DS) === "code");
check("ds: code floor, trivial -> nano (one below)", effectiveBand("code", "trivial", "trivial", BAND_DS) === "nano");
check("ds: nano floor, trivial -> nano (clamp)", effectiveBand("nano", "trivial", "trivial", BAND_DS) === "nano");
check("ds: deep floor protected on trivial", effectiveBand("deep", "trivial", "trivial", BAND_DS) === "deep");
check("ds: bump still works on complex planning", effectiveBand("balanced", "complex", "needs-plan", BAND_DS) === "deep");
check("ds: no downshift on build stage", effectiveBand("balanced", "standard", "plan-approved", BAND_DS) === "balanced");
check("default config: trivial keeps floor (no downshift)", effectiveBand("balanced", "trivial", "trivial", BAND) === "balanced");

if (failures) {
	console.error(`\n${failures} check(s) failed`);
	process.exit(1);
}
console.log("\nall dev-team extension checks passed");
