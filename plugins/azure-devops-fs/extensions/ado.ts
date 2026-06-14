// ado.ts — "Azure DevOps as a filesystem" for Oh-My-Pi.
//
// One tool, `ado`, dispatched on `op`. Reads (repo/files/PRs/diffs) accept the
// ado:// and adopr:// URI sugar; mutations (create/checkout/push/comment/vote)
// mirror OMP's `github` tool. Standalone: PAT auth, SQLite read cache, git
// worktrees. No dependency on any other plugin.
//
// Env: AZURE_DEVOPS_PAT (required), AZURE_DEVOPS_ORG, AZURE_DEVOPS_PROJECT.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { cacheGet, cacheSet } from "./lib/cache.ts";
import {
	fmtBuilds,
	fmtChanges,
	fmtChecks,
	fmtFile,
	fmtItems,
	fmtPipelines,
	fmtPr,
	fmtPrList,
	fmtRepo,
	fmtWorkItem,
} from "./lib/format.ts";
import { AdoError, authHeader, makeClient, resolveEnv } from "./lib/rest.ts";
import { isAdoUri, parseAdoUri } from "./lib/uri.ts";
import { prCheckout, prPush, prWorktreePath } from "./lib/worktree.ts";

const READ_TTL = 120; // seconds; reads are cached, mutations never are
// Ops that mutate / have side effects and require confirmation when no UI.
const CONFIRM = new Set(["pr_abandon", "pr_complete", "build_run"]);
const READ_OPS = [
	"repo_view", "repo_ls", "repo_read", "pr_view", "pr_list", "pr_files",
	"pr_checks", "work_item", "build_list", "build_logs", "pipeline_list",
];
const VOTE: Record<string, number> = {
	approve: 10,
	"approve-suggestions": 5,
	reset: 0,
	waiting: -5,
	reject: -10,
};

/* eslint-disable @typescript-eslint/no-explicit-any */
function text(s: string, details?: Record<string, unknown>) {
	return { content: [{ type: "text" as const, text: s }], details };
}

export default function ado(pi: ExtensionAPI) {
	const { z } = pi.zod;
	pi.setLabel("azure-devops-fs");

	pi.registerTool({
		name: "ado",
		label: "Azure DevOps",
		description:
			"Azure DevOps as a filesystem. Reads accept ado:// / adopr:// URIs.\n" +
			"Read: repo_view, repo_ls, repo_read, pr_view, pr_list, pr_files, pr_diff (paginated, skip=), pr_checks (gates/policies/CI), work_item, search_code.\n" +
			"CI: pipeline_list, build_list, build_logs, build_run, pipeline_watch.\n" +
			"Write: pr_create, pr_checkout, pr_push, pr_comment, pr_vote, pr_abandon, pr_complete (merge/auto-complete).\n" +
			"URIs: ado://{org}/{project}/{repo}/{path}@{ref}  ·  adopr://{org}/{project}/{repo}/{id}[/diff[/path]].\n" +
			"org/project default from AZURE_DEVOPS_ORG/PROJECT. Needs AZURE_DEVOPS_PAT.",
		parameters: z.object({
			op: z.enum([
				"repo_view",
				"repo_ls",
				"repo_read",
				"pr_view",
				"pr_list",
				"pr_files",
				"pr_diff",
				"pr_create",
				"pr_checkout",
				"pr_push",
				"pr_comment",
				"pr_vote",
				"pr_abandon",
				"pr_complete",
				"pr_checks",
				"pipeline_watch",
				"pipeline_list",
				"build_list",
				"build_logs",
				"build_run",
				"work_item",
				"search_code",
			]),
			uri: z.string().optional().describe("ado:// or adopr:// shortcut; fills org/project/repo/path/ref/id"),
			org: z.string().optional(),
			project: z.string().optional(),
			repo: z.string().optional(),
			path: z.string().optional().describe("repo path (repo_ls/repo_read) or single file for pr_diff"),
			ref: z.string().optional().describe("branch/tag/commit (default: repo default branch)"),
			id: z.number().optional().describe("PR id or work item id"),
			title: z.string().optional(),
			description: z.string().optional(),
			source: z.string().optional().describe("pr_create: source branch"),
			target: z.string().optional().describe("pr_create: target branch"),
			draft: z.boolean().optional(),
			status: z.string().optional().describe("pr_list: active|completed|abandoned|all"),
			limit: z.number().optional(),
			comment: z.string().optional().describe("pr_comment body"),
			threadId: z.number().optional().describe("pr_comment: reply to this thread"),
			vote: z.enum(["approve", "approve-suggestions", "reset", "waiting", "reject"]).optional(),
			query: z.string().optional().describe("search_code query"),
			buildId: z.number().optional().describe("pipeline_watch/build_logs build id"),
			definitionId: z.number().optional().describe("build_run: pipeline/definition id to queue"),
			skip: z.number().optional().describe("pagination offset (pr_diff files, lists)"),
			mergeStrategy: z.enum(["squash", "rebase", "rebaseMerge", "noFastForward"]).optional().describe("pr_complete merge strategy"),
			autoComplete: z.boolean().optional().describe("pr_complete: set auto-complete instead of completing now"),
			type: z.string().optional().describe("work_item create type, e.g. Bug, Task"),
			force: z.boolean().optional(),
			confirm: z.boolean().optional().describe("required for destructive ops when no UI"),
		}),
		async execute(_id, p: any, signal, onUpdate, ctx) {
			try {
				// Resolve target from uri sugar if present.
				let { org, project, repo, path, ref, id } = p;
				if (isAdoUri(p.uri)) {
					const t = parseAdoUri(p.uri, {
						org: process.env.AZURE_DEVOPS_ORG,
						project: process.env.AZURE_DEVOPS_PROJECT,
						repo,
					});
					org = t.org;
					project = t.project;
					repo = t.repo;
					if (t.kind === "repo") {
						path = t.path;
						ref = t.ref ?? ref;
					} else {
						id = t.id;
						if (t.diff) p._diff = t.diff;
					}
				}
				const env = resolveEnv({ org, project });
				const c = makeClient(env, signal ?? undefined);
				const repoEnc = repo ? encodeURIComponent(repo) : "";
				const verDesc = (r?: string) =>
					r ? { "versionDescriptor.version": r, "versionDescriptor.versionType": "branch" } : {};

				// Confirmation gate for destructive / side-effecting ops.
				if (CONFIRM.has(p.op) || (p.op === "pr_vote" && p.vote === "reject") || (p.op === "pr_push" && p.force)) {
					const what = `${p.op}${p.vote ? ` (${p.vote})` : ""} on ${repo ?? "?"}${id ? ` !${id}` : ""}`;
					const ok = ctx.hasUI ? await ctx.ui.confirm("Azure DevOps", `Confirm ${what}?`) : p.confirm === true;
					if (!ok)
						return text(`Aborted ${what}. ${ctx.hasUI ? "" : "Pass confirm:true to proceed without a UI."}`);
				}

				const cacheKey = JSON.stringify([p.op, env.org, env.project, repo, path, ref, id, p._diff, p.status, p.limit, p.skip, p.query, p.buildId, p.definitionId]);
				if (READ_OPS.includes(p.op)) {
					const hit = cacheGet(cacheKey, READ_TTL);
					if (hit) return text(hit, { cached: true });
				}

				const need = (v: unknown, name: string) => {
					if (v === undefined || v === null || v === "") throw new AdoError(`op ${p.op} requires '${name}'`);
				};

				switch (p.op) {
					case "repo_view": {
						need(repo, "repo");
						const r = await c.get<any>(`/_apis/git/repositories/${repoEnc}`);
						const out = fmtRepo(r);
						cacheSet(cacheKey, out);
						return text(out, { sourceUrl: r.webUrl });
					}
					case "repo_ls": {
						need(repo, "repo");
						const r = await c.get<any>(`/_apis/git/repositories/${repoEnc}/items`, {
							scopePath: path ?? "/",
							recursionLevel: "OneLevel",
							...verDesc(ref),
						});
						const out = fmtItems(r.value ?? [], { repo, path: path ?? "/", ref });
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "repo_read": {
						need(repo, "repo");
						need(path, "path");
						const r = await c.get<any>(`/_apis/git/repositories/${repoEnc}/items`, {
							path,
							includeContent: true,
							...verDesc(ref),
						});
						const out = fmtFile(path, ref, r.content ?? "(empty)");
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "pr_view": {
						need(repo, "repo");
						need(id, "id");
						const pr = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}`);
						let threads: any[] | undefined;
						try {
							threads = (await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/threads`)).value;
						} catch {
							/* threads optional */
						}
						let workItems: any[] | undefined;
						try {
							workItems = (await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/workitems`)).value;
						} catch {
							/* work-item links optional */
						}
						const out = fmtPr(pr, threads, { workItems });
						cacheSet(cacheKey, out);
						return text(out, { sourceUrl: pr._links?.web?.href });
					}
					case "pr_list": {
						need(repo, "repo");
						const r = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests`, {
							"searchCriteria.status": p.status ?? "active",
							$top: Math.min(p.limit ?? 20, 100),
						});
						const out = fmtPrList(r.value ?? []);
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "pr_files": {
						need(repo, "repo");
						need(id, "id");
						const its = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/iterations`);
						const last = (its.value ?? []).at(-1);
						if (!last) return text("(no iterations)");
						// Paginate the iteration changes ($top/$skip) so large PRs aren't truncated.
						const changes = await c.listSkip<any>(
							`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/iterations/${last.id}/changes`,
							{},
							{ key: "changeEntries", top: 1000, cap: 5000 },
						);
						const out = fmtChanges(changes);
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "pr_diff": {
						need(repo, "repo");
						need(id, "id");
						const pr = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}`);
						const base = pr.lastMergeTargetCommit?.commitId;
						const src = pr.lastMergeSourceCommit?.commitId;
						const its = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/iterations`);
						const last = (its.value ?? []).at(-1);
						const ch = last
							? await c.listSkip<any>(
									`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/iterations/${last.id}/changes`,
									{},
									{ key: "changeEntries", top: 1000, cap: 5000 },
								)
							: [];
						const want = p._diff?.path ?? path;
						const PAGE = 25;
						const skip = Math.max(0, p.skip ?? 0);
						let files = ch.filter((e: any) => e.item?.path && !e.item.isFolder);
						if (want) files = files.filter((e: any) => e.item.path === want || e.item.path === `/${want}`);
						const total = files.length;
						files = want ? files.slice(0, 1) : files.slice(skip, skip + PAGE);
						const more = !want && skip + files.length < total;
						const contentAt = async (commit: string | undefined, fp: string) => {
							if (!commit) return "";
							try {
								const r = await c.get<any>(`/_apis/git/repositories/${repoEnc}/items`, {
									path: fp,
									includeContent: true,
									"versionDescriptor.version": commit,
									"versionDescriptor.versionType": "commit",
								});
								return r.content ?? "";
							} catch {
								return "";
							}
						};
						const isBinary = (s: string) => s.includes("\u0000");
						const dir = mkdtempSync(join(tmpdir(), "ado-diff-"));
						const parts: string[] = [];
						for (const e of files) {
							const fp = e.item.path as string;
							const a = await contentAt(base, fp);
							const b = await contentAt(src, fp);
							if (isBinary(a) || isBinary(b)) {
								parts.push(`### ${fp} (${e.changeType})\n\n_(binary file — diff omitted)_`);
								continue;
							}
							const af = join(dir, "a");
							const bf = join(dir, "b");
							writeFileSync(af, a);
							writeFileSync(bf, b);
							let d = "";
							try {
								execFileSync("git", ["diff", "--no-index", "--", af, bf], { encoding: "utf8" });
							} catch (err: any) {
								d = String(err.stdout ?? ""); // git diff exits 1 when files differ
							}
							parts.push(`### ${fp} (${e.changeType})\n\n\`\`\`diff\n${d.replace(new RegExp(dir + "/", "g"), "")}\n\`\`\``);
						}
						const range = want ? "" : ` ${skip + 1}-${skip + files.length} of ${total}`;
						const hint = more ? `\n\n_More files: re-run with skip=${skip + PAGE}._` : "";
						return text(`# PR !${id} diff (${files.length} file${files.length === 1 ? "" : "s"}${range})\n\n${parts.join("\n\n")}${hint}`);
					}
					case "pr_create": {
						need(repo, "repo");
						need(p.title, "title");
						need(p.source, "source");
						need(p.target, "target");
						const pr = await c.send<any>("POST", `/_apis/git/repositories/${repoEnc}/pullRequests`, {
							sourceRefName: p.source.startsWith("refs/") ? p.source : `refs/heads/${p.source}`,
							targetRefName: p.target.startsWith("refs/") ? p.target : `refs/heads/${p.target}`,
							title: p.title,
							description: p.description ?? "",
							isDraft: p.draft ?? false,
						});
						return text(`Created PR !${pr.pullRequestId}: ${pr.title}\n${pr._links?.web?.href ?? ""}`, {
							sourceUrl: pr._links?.web?.href,
							prId: pr.pullRequestId,
						});
					}
					case "pr_checkout": {
						need(repo, "repo");
						need(id, "id");
						const pr = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}`);
						const res = prCheckout(env, repo, pr.sourceRefName, { prId: id, force: p.force });
						return text(
							`${res.reused ? "Reused" : "Checked out"} PR !${id} (${res.branch}) at ${res.worktreePath}`,
							{ worktreePath: res.worktreePath, branch: res.branch },
						);
					}
					case "pr_push": {
						need(repo, "repo");
						need(id, "id");
						const pr = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}`);
						const branch = String(pr.sourceRefName).replace("refs/heads/", "");
						const wt = prWorktreePath(env, repo, id);
						const out = prPush(env, wt, branch, { force: p.force });
						return text(`Pushed ${branch} from ${wt}\n${out}`.trim());
					}
					case "pr_comment": {
						need(repo, "repo");
						need(id, "id");
						need(p.comment, "comment");
						if (p.threadId) {
							await c.send("POST", `/_apis/git/repositories/${repoEnc}/pullRequests/${id}/threads/${p.threadId}/comments`, {
								content: p.comment,
								commentType: 1,
							});
							return text(`Replied on thread ${p.threadId} of PR !${id}`);
						}
						const t = await c.send<any>("POST", `/_apis/git/repositories/${repoEnc}/pullRequests/${id}/threads`, {
							comments: [{ parentCommentId: 0, content: p.comment, commentType: 1 }],
							status: 1,
						});
						return text(`Added comment thread ${t.id} on PR !${id}`);
					}
					case "pr_vote": {
						need(repo, "repo");
						need(id, "id");
						need(p.vote, "vote");
						const me = await c.selfId();
						await c.send("PATCH", `/_apis/git/repositories/${repoEnc}/pullRequests/${id}/reviewers/${me.id}`, {
							vote: VOTE[p.vote],
						});
						return text(`Voted '${p.vote}' on PR !${id} as ${me.displayName}`);
					}
					case "pr_abandon": {
						need(repo, "repo");
						need(id, "id");
						await c.send("PATCH", `/_apis/git/repositories/${repoEnc}/pullRequests/${id}`, { status: "abandoned" });
						return text(`Abandoned PR !${id}`);
					}
					case "work_item": {
						if (p.title && p.type) {
							const wi = await c.send<any>(
								"POST",
								`/_apis/wit/workitems/$${encodeURIComponent(p.type)}`,
								[
									{ op: "add", path: "/fields/System.Title", value: p.title },
									...(p.description ? [{ op: "add", path: "/fields/System.Description", value: p.description }] : []),
								],
								{},
								{ contentType: "application/json-patch+json" },
							);
							return text(`Created ${p.type} #${wi.id}: ${p.title}`, { id: wi.id });
						}
						need(id, "id");
						const wi = await c.get<any>(`/_apis/wit/workitems/${id}`, { $expand: "all" });
						const out = fmtWorkItem(wi);
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "search_code": {
						need(p.query, "query");
						const url = `https://almsearch.dev.azure.com/${encodeURIComponent(env.org)}/${encodeURIComponent(env.project)}/_apis/search/codesearchresults?api-version=7.1`;
						const res = await fetch(url, {
							method: "POST",
							headers: { Authorization: authHeader(env.pat), "Content-Type": "application/json" },
							body: JSON.stringify({ searchText: p.query, $top: Math.min(p.limit ?? 15, 50), filters: repo ? { RepositoryFilters: [repo] } : undefined }),
							signal: signal ?? undefined,
						});
						if (res.status === 404)
							return text("Code Search is not installed for this org (Marketplace extension 'Code Search'). search_code unavailable.");
						if (!res.ok) throw new AdoError(`search_code -> ${res.status}: ${(await res.text()).slice(0, 200)}`);
						const j: any = await res.json();
						const rows = (j.results ?? []).map(
							(r: any) => `- ${r.repository?.name}/${r.path}  (${r.matches?.content?.length ?? 0} match)`,
						);
						return text(`# Code search "${p.query}" (${j.count ?? rows.length})\n${rows.join("\n")}`);
					}
					case "pipeline_watch": {
						need(p.buildId, "buildId");
						const tailEnd = Date.now() + 20 * 60 * 1000; // 20 min cap
						let last = "";
						while (Date.now() < tailEnd) {
							if (signal?.aborted) return text(`Aborted watching build ${p.buildId} (last: ${last})`);
							const b = await c.get<any>(`/_apis/build/builds/${p.buildId}`);
							last = `${b.status}${b.result ? `/${b.result}` : ""}`;
							onUpdate?.({ content: [{ type: "text", text: `build ${p.buildId}: ${last}` }] });
							if (b.status === "completed")
								return text(`Build ${p.buildId} ${b.result} — ${b._links?.web?.href ?? ""}`, {
									status: b.status,
									conclusion: b.result,
								});
							await new Promise((r) => setTimeout(r, 3000));
						}
						return text(`Build ${p.buildId} still running after 20m (last: ${last})`);
					}
					case "pr_checks": {
						need(repo, "repo");
						need(id, "id");
						const pr = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}`);
						// Branch-policy evaluations (the merge gates). Needs the project GUID
						// in the artifactId, and Policy (read) on the PAT.
						let policies: any[] = [];
						try {
							const pid = await c.projectId();
							policies =
								(await c.get<any>(`/_apis/policy/evaluations`, {
									artifactId: `vstfs:///CodeReview/CodeReviewId/${pid}/${id}`,
								})).value ?? [];
						} catch {
							/* policy read optional */
						}
						// External statuses posted to the PR.
						let statuses: any[] = [];
						try {
							statuses = (await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}/statuses`)).value ?? [];
						} catch {
							/* statuses optional */
						}
						// Build-validation runs queued against the PR merge ref.
						let builds: any[] = [];
						try {
							builds = await c.listToken<any>(`/_apis/build/builds`, { branchName: `refs/pull/${id}/merge` }, { cap: 50 });
						} catch {
							/* builds optional */
						}
						const out = fmtChecks(Number(id), { mergeStatus: pr.mergeStatus, policies, statuses, builds });
						cacheSet(cacheKey, out);
						return text(out, { sourceUrl: pr._links?.web?.href });
					}
					case "pr_complete": {
						need(repo, "repo");
						need(id, "id");
						const pr = await c.get<any>(`/_apis/git/repositories/${repoEnc}/pullRequests/${id}`);
						const completionOptions = {
							mergeStrategy: p.mergeStrategy ?? "squash",
							deleteSourceBranch: false,
							bypassPolicy: false,
						};
						if (p.autoComplete) {
							const me = await c.selfId();
							await c.send("PATCH", `/_apis/git/repositories/${repoEnc}/pullRequests/${id}`, {
								autoCompleteSetBy: { id: me.id },
								completionOptions,
							});
							return text(`Set auto-complete on PR !${id} (${completionOptions.mergeStrategy}); it merges once policies pass.`);
						}
						await c.send("PATCH", `/_apis/git/repositories/${repoEnc}/pullRequests/${id}`, {
							status: "completed",
							lastMergeSourceCommit: pr.lastMergeSourceCommit,
							completionOptions,
						});
						return text(`Completed (merged) PR !${id} via ${completionOptions.mergeStrategy}.`);
					}
					case "pipeline_list": {
						const defs = await c.listToken<any>(
							`/_apis/build/definitions`,
							{ $top: Math.min(p.limit ?? 100, 1000) },
							{ cap: p.limit ?? 300 },
						);
						const out = fmtPipelines(defs);
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "build_list": {
						const q: Record<string, string | number> = {};
						if (ref) q.branchName = String(ref).startsWith("refs/") ? ref : `refs/heads/${ref}`;
						if (p.status) q.statusFilter = p.status; // inProgress|completed|notStarted|all
						if (p.definitionId) q.definitions = p.definitionId;
						const builds = await c.listToken<any>(
							`/_apis/build/builds`,
							{ ...q, $top: Math.min(p.limit ?? 20, 100) },
							{ cap: p.limit ?? 50 },
						);
						const out = fmtBuilds(builds);
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "build_logs": {
						need(p.buildId, "buildId");
						const logs = (await c.get<any>(`/_apis/build/builds/${p.buildId}/logs`)).value ?? [];
						if (!logs.length) return text(`Build ${p.buildId}: no logs yet`);
						const lastLog = logs.at(-1);
						const raw = await c.get<string>(`/_apis/build/builds/${p.buildId}/logs/${lastLog.id}`, {}, { raw: true });
						const all = String(raw).split("\n");
						const tail = all.slice(-200);
						const out = `# Build ${p.buildId} — log ${lastLog.id} (last ${tail.length}/${all.length} lines)\n\n\`\`\`\n${tail.join("\n")}\n\`\`\``;
						cacheSet(cacheKey, out);
						return text(out);
					}
					case "build_run": {
						need(p.definitionId, "definitionId");
						const b = await c.send<any>("POST", `/_apis/build/builds`, {
							definition: { id: p.definitionId },
							...(ref ? { sourceBranch: String(ref).startsWith("refs/") ? ref : `refs/heads/${ref}` } : {}),
						});
						return text(
							`Queued build #${b.id} (${b.definition?.name ?? p.definitionId}) on ${(b.sourceBranch ?? "").replace("refs/heads/", "")} — ${b._links?.web?.href ?? ""}`.trimEnd(),
							{ buildId: b.id },
						);
					}
					default:
						return text(`Unknown op '${p.op}'`);
				}
			} catch (e) {
				const msg = e instanceof Error ? e.message : String(e);
				return { content: [{ type: "text" as const, text: `ado error: ${msg}` }], isError: true };
			}
		},
	});
}
