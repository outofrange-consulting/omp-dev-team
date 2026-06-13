// PR checkout/push for Azure DevOps repos, using git with PAT auth injected via
// http.extraheader. Checkouts live under ~/.omp/wt/<key>/pr-<id> (a single-
// branch clone of the PR source branch), mirroring the gh tool's worktree dir.

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { authHeader, type AdoEnv } from "./rest.ts";

function wtRoot(): string {
	return process.env.OMP_WT_DIR ?? join(homedir(), ".omp", "wt");
}

function keyFor(env: AdoEnv, repo: string): string {
	return `${env.org}_${env.project}_${repo}`.replace(/[^A-Za-z0-9._-]/g, "-");
}

export function prWorktreePath(env: AdoEnv, repo: string, prId: number): string {
	return join(wtRoot(), keyFor(env, repo), `pr-${prId}`);
}

export function repoCloneUrl(env: AdoEnv, repo: string): string {
	return `https://dev.azure.com/${encodeURIComponent(env.org)}/${encodeURIComponent(
		env.project,
	)}/_git/${encodeURIComponent(repo)}`;
}

function git(args: string[], cwd: string, pat: string): string {
	// Inject auth without writing the PAT to disk/remote URL.
	const full = ["-c", `http.extraheader=Authorization: ${authHeader(pat)}`, ...args];
	return execFileSync("git", full, { cwd, encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
}

export interface CheckoutResult {
	worktreePath: string;
	branch: string;
	reused: boolean;
}

export function prCheckout(
	env: AdoEnv,
	repo: string,
	sourceRefName: string,
	opts: { force?: boolean; prId: number },
): CheckoutResult {
	const branch = sourceRefName.replace(/^refs\/heads\//, "");
	const dest = join(wtRoot(), keyFor(env, repo), `pr-${opts.prId}`);
	if (existsSync(join(dest, ".git"))) {
		if (!opts.force) {
			// refresh and reuse
			try {
				git(["fetch", "origin", branch], dest, env.pat);
				git(["checkout", branch], dest, env.pat);
				git(["reset", "--hard", `origin/${branch}`], dest, env.pat);
			} catch {
				/* best-effort refresh */
			}
			return { worktreePath: dest, branch, reused: true };
		}
	}
	const url = repoCloneUrl(env, repo);
	execFileSync(
		"git",
		[
			"-c",
			`http.extraheader=Authorization: ${authHeader(env.pat)}`,
			"clone",
			"--single-branch",
			"--branch",
			branch,
			url,
			dest,
		],
		{ encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
	);
	return { worktreePath: dest, branch, reused: false };
}

export function prPush(
	env: AdoEnv,
	worktreePath: string,
	branch: string,
	opts: { force?: boolean } = {},
): string {
	const args = ["push", "origin", `HEAD:refs/heads/${branch}`];
	if (opts.force) args.splice(1, 0, "--force-with-lease");
	return git(args, worktreePath, env.pat);
}
