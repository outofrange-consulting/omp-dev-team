// impl-verify-core.ts — pure, side-effect-free logic for the /impl-verify
// deterministic build+test gate. Kept separate from the extension so it can be
// unit-tested without spawning processes or loading OMP.
//
// The idea (ported from cde-dotnetcc's impl-build.js determinism): the mechanical
// parts of an implement→verify loop — which build/test command to run, whether
// it passed, and how many fix attempts are left — are decided in CODE, not by
// the model reasoning over raw logs. The agent runs one command and reads a
// one-line verdict + a bounded failure tail, instead of running build, reading
// full output, running test, reading full output, and counting attempts itself.

export type Stack = "dotnet" | "node" | "python" | "go" | "rust";

export interface StackCommands {
	build: string;
	test: string;
	format?: string;
}

// Defaults run the STRICT build for each stack, so the no-disable-analyzers rule
// is enforced by the toolchain here (e.g. dotnet warnings-as-errors). Override
// per-repo via .omp/dev-team.json -> implVerify.stacks.<stack>.
export const DEFAULT_STACKS: Record<Stack, StackCommands> = {
	dotnet: {
		build: "dotnet build -warnaserror",
		test: "dotnet test --nologo",
		format: "dotnet format --verify-no-changes",
	},
	node: {
		build: "npm run build --if-present",
		test: "npm test --silent",
		format: "npx --no-install biome check .",
	},
	python: {
		build: "ruff check .",
		test: "pytest -q",
		format: "ruff format --check .",
	},
	go: { build: "go build ./...", test: "go test ./...", format: "gofmt -l ." },
	rust: {
		build: "cargo build --locked",
		test: "cargo test --locked",
		format: "cargo fmt --check",
	},
};

// Marker files that identify a stack, highest-priority first. dotnet wins when a
// repo mixes a .NET solution with a JS frontend, because the strict .NET build is
// the one most often skipped by hand.
const STACK_MARKERS: Array<[Stack, RegExp]> = [
	["dotnet", /\.(csproj|fsproj|sln)$/i],
	["rust", /(^|\/)Cargo\.toml$/i],
	["go", /(^|\/)go\.mod$/i],
	["python", /(^|\/)(pyproject\.toml|setup\.cfg|requirements\.txt)$/i],
	["node", /(^|\/)package\.json$/i],
];

// Detect the stack from a list of repo file paths (relative or absolute).
export function detectStack(files: string[]): Stack | null {
	for (const [stack, re] of STACK_MARKERS) {
		if (files.some((f) => re.test(f))) return stack;
	}
	return null;
}

export interface VerifyState {
	attempts: number; // consecutive failed verify attempts
	lastStatus?: VerifyStatus;
	updatedAt?: string;
}

export type VerifyStatus = "PASS" | "FAIL" | "HALT";

export interface VerifyInput {
	prev: VerifyState;
	buildOk: boolean;
	testOk: boolean;
	skipTests: boolean;
	maxFixes: number;
}

export interface VerifyResult {
	status: VerifyStatus;
	state: VerifyState;
	line: string; // one-line verdict for the agent
}

// Decide the verdict deterministically and advance the bounded fix counter.
//   PASS  — build ok and (tests ok or skipped); counter resets.
//   FAIL  — something failed and there are fix attempts left; counter++.
//   HALT  — failed and the fix budget is exhausted; escalate to a human.
export function computeVerdict(input: VerifyInput): VerifyResult {
	const { prev, buildOk, testOk, skipTests, maxFixes } = input;
	const passed = buildOk && (skipTests || testOk);

	if (passed) {
		return {
			status: "PASS",
			state: { attempts: 0, lastStatus: "PASS" },
			line: skipTests
				? "PASS — build green (tests skipped)."
				: "PASS — build + tests green.",
		};
	}

	const attempts = prev.attempts + 1;
	const failed = !buildOk ? "build" : "tests";
	if (attempts >= Math.max(1, maxFixes)) {
		return {
			status: "HALT",
			state: { attempts, lastStatus: "HALT" },
			line: `HALT — ${failed} still failing after ${attempts}/${maxFixes} fix attempts. Stop auto-fixing and escalate to the human.`,
		};
	}
	return {
		status: "FAIL",
		state: { attempts, lastStatus: "FAIL" },
		line: `FAIL — ${failed} failing (fix attempt ${attempts}/${maxFixes}). Fix the cause and re-run /impl-verify.`,
	};
}

// Keep the last N non-empty lines of command output as a compact failure tail.
export function tail(output: string, lines = 25): string {
	const kept = output
		.split(/\r?\n/)
		.filter((l) => l.trim().length > 0)
		.slice(-lines);
	return kept.join("\n");
}
