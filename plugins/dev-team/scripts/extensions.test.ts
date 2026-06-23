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
import { globToRegExp, matchesAny } from "../extensions/lib/shared.ts";

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

if (failures) {
	console.error(`\n${failures} check(s) failed`);
	process.exit(1);
}
console.log("\nall dev-team extension checks passed");
