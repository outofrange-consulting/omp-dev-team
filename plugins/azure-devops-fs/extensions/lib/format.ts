// Markdown formatting for ado tool results. Loose typing on API payloads.
/* eslint-disable @typescript-eslint/no-explicit-any */

function webUrl(o: any): string | undefined {
	return o?._links?.web?.href ?? o?.url;
}

export function fmtRepo(r: any): string {
	const lines = [
		`# ${r.project?.name ?? ""}/${r.name}`,
		r.webUrl ? r.webUrl : "",
		`Default branch: ${(r.defaultBranch ?? "").replace("refs/heads/", "") || "(none)"}`,
		r.size != null ? `Size: ${r.size} bytes` : "",
		r.isDisabled ? "DISABLED" : "",
	].filter(Boolean);
	return lines.join("\n");
}

export function fmtItems(items: any[], target: { repo: string; path: string; ref?: string }): string {
	const head = `# ${target.repo}:${target.path}${target.ref ? `@${target.ref}` : ""}  (${items.length})`;
	const rows = items
		.filter((i) => i.path !== target.path)
		.sort((a, b) => Number(b.isFolder) - Number(a.isFolder) || String(a.path).localeCompare(b.path))
		.map((i) => `${i.isFolder ? "📁" : "📄"} ${i.path}`);
	return [head, ...rows].join("\n");
}

export function fmtFile(path: string, ref: string | undefined, content: string): string {
	return `# ${path}${ref ? `@${ref}` : ""}\n\n${content}`;
}

function reviewerVote(v: number): string {
	return (
		{ 10: "✓approved", 5: "✓approved w/ suggestions", 0: "no vote", "-5": "⏳waiting", "-10": "✗rejected" } as Record<string, string>
	)[String(v)] ?? String(v);
}

// Azure mergeStatus → human label (conflicts are the common blocker).
function mergeLabel(s?: string): string {
	return (
		{
			succeeded: "✓ mergeable",
			conflicts: "✗ conflicts",
			queued: "⏳ checking merge",
			rejectedByPolicy: "✗ blocked by policy",
			failure: "✗ merge failure",
			notSet: "merge not evaluated",
		} as Record<string, string>
	)[String(s)] ?? String(s ?? "");
}

export function fmtPr(pr: any, threads?: any[], extra?: { workItems?: any[] }): string {
	const lines: string[] = [
		`# !${pr.pullRequestId} ${pr.title}`,
		webUrl(pr) ?? "",
		`Status: ${pr.status}${pr.isDraft ? " (draft)" : ""}  ·  ${(pr.sourceRefName ?? "").replace("refs/heads/", "")} → ${(pr.targetRefName ?? "").replace("refs/heads/", "")}`,
		`Author: ${pr.createdBy?.displayName ?? "?"}  ·  ${pr.creationDate ?? ""}`,
	];
	// Azure specifics: merge status / conflicts, auto-complete, labels.
	const merge = mergeLabel(pr.mergeStatus);
	const ac = pr.autoCompleteSetBy?.displayName ? `  ·  auto-complete by ${pr.autoCompleteSetBy.displayName}` : "";
	if (merge || ac) lines.push(`Merge: ${merge}${ac}`);
	if (pr.labels?.length) lines.push(`Labels: ${pr.labels.map((l: any) => l.name).join(", ")}`);
	if (pr.reviewers?.length) {
		lines.push(
			"Reviewers: " +
				pr.reviewers
					.map((r: any) => `${r.displayName}${r.isRequired ? "*" : ""}(${reviewerVote(r.vote ?? 0)})`)
					.join(", ") +
				(pr.reviewers.some((r: any) => r.isRequired) ? "   (*required)" : ""),
		);
	}
	if (extra?.workItems?.length) {
		lines.push(`Work items: ${extra.workItems.map((w: any) => `#${w.id}`).join(", ")}`);
	}
	if (pr.description) lines.push("", pr.description.trim());
	if (threads?.length) {
		const visible = threads.filter((t) => t.comments?.some((c: any) => c.commentType !== "system" && c.content));
		if (visible.length) {
			lines.push("", `## Threads (${visible.length})`);
			for (const t of visible) {
				const status = t.status ? ` [${t.status}]` : "";
				for (const c of t.comments ?? []) {
					if (!c.content || c.commentType === "system") continue;
					lines.push(`- **${c.author?.displayName ?? "?"}**${status}: ${String(c.content).trim()}`);
				}
			}
		}
	}
	return lines.filter((l) => l !== undefined).join("\n");
}

export function fmtPrList(prs: any[]): string {
	const head = `# Pull requests (${prs.length})`;
	const rows = prs.map(
		(p) =>
			`- !${p.pullRequestId} ${p.title} — ${p.status}${p.isDraft ? "/draft" : ""} by ${p.createdBy?.displayName ?? "?"} (${(p.sourceRefName ?? "").replace("refs/heads/", "")} → ${(p.targetRefName ?? "").replace("refs/heads/", "")})`,
	);
	return [head, ...rows].join("\n");
}

export function fmtChanges(changes: any[]): string {
	const head = `# Changed files (${changes.length})`;
	const rows = changes.map((c) => `${c.changeType?.toUpperCase?.() ?? "EDIT"}\t${c.item?.path ?? c.originalPath ?? "?"}`);
	return [head, ...rows].join("\n");
}

// --- Gates / policies / CI -------------------------------------------------

function policyIcon(s?: string): string {
	return (
		{ approved: "✓", queued: "⏳", running: "⏳", rejected: "✗", broken: "⚠", notApplicable: "·" } as Record<string, string>
	)[String(s)] ?? "?";
}
function statusIcon(s?: string): string {
	return (
		{ succeeded: "✓", failed: "✗", error: "⚠", pending: "⏳", notApplicable: "·", notSet: "·" } as Record<string, string>
	)[String(s)] ?? "?";
}
function buildIcon(b: any): string {
	if (b.status !== "completed") return "⏳";
	return ({ succeeded: "✓", partiallySucceeded: "⚠", failed: "✗", canceled: "⊘" } as Record<string, string>)[String(b.result)] ?? "?";
}

// Unified "what blocks the merge": Azure branch-policy evaluations + external
// PR statuses + associated build-validation runs + raw mergeStatus.
export function fmtChecks(prId: number, data: { mergeStatus?: string; policies?: any[]; statuses?: any[]; builds?: any[] }): string {
	const lines: string[] = [`# PR !${prId} gates & checks`, `Merge: ${mergeLabel(data.mergeStatus)}`];

	const pols = data.policies ?? [];
	const blocking = pols.filter((p) => p.configuration?.isBlocking);
	const failing = pols.filter((p) => p.status === "rejected" || p.status === "broken");
	lines.push(
		"",
		`## Branch policies (${pols.length}; ${blocking.length} blocking, ${failing.length} failing)`,
	);
	for (const p of pols) {
		const name = p.configuration?.type?.displayName ?? p.configuration?.type?.id ?? "policy";
		lines.push(`- ${policyIcon(p.status)} ${name}${p.configuration?.isBlocking ? " (blocking)" : ""} — ${p.status}`);
	}
	if (!pols.length) lines.push("- (none configured, or policy read not permitted)");

	const sts = data.statuses ?? [];
	if (sts.length) {
		lines.push("", `## PR statuses (${sts.length})`);
		for (const s of sts) {
			const ctx = [s.context?.genre, s.context?.name].filter(Boolean).join("/");
			lines.push(`- ${statusIcon(s.state)} ${ctx || "status"} — ${s.state}${s.description ? `: ${s.description}` : ""}`);
		}
	}

	const builds = data.builds ?? [];
	if (builds.length) {
		lines.push("", `## Build validation runs (${builds.length})`);
		for (const b of builds) {
			lines.push(`- ${buildIcon(b)} ${b.definition?.name ?? "build"} #${b.id} — ${b.status}${b.result ? `/${b.result}` : ""}  ${webUrl(b) ?? ""}`.trimEnd());
		}
	}
	return lines.join("\n");
}

export function fmtBuilds(builds: any[]): string {
	const head = `# Builds (${builds.length})`;
	const rows = builds.map(
		(b) =>
			`- ${buildIcon(b)} #${b.id} ${b.definition?.name ?? "?"} [${b.status}${b.result ? `/${b.result}` : ""}] ${(b.sourceBranch ?? "").replace("refs/heads/", "")} — ${b.buildNumber ?? ""}`,
	);
	return [head, ...rows].join("\n");
}

export function fmtPipelines(defs: any[]): string {
	const head = `# Pipelines (${defs.length})`;
	const rows = defs.map((d) => `- ${d.id}\t${d.name}${d.folder && d.folder !== "\\" ? `  (${d.folder})` : ""}`);
	return [head, ...rows].join("\n");
}

export function fmtWorkItem(wi: any): string {
	const f = wi.fields ?? {};
	return [
		`# WI #${wi.id} ${f["System.WorkItemType"] ?? ""}: ${f["System.Title"] ?? ""}`,
		`State: ${f["System.State"] ?? "?"}  ·  Assigned: ${f["System.AssignedTo"]?.displayName ?? "—"}`,
		f["System.Description"] ? `\n${String(f["System.Description"]).replace(/<[^>]+>/g, "").trim()}` : "",
	]
		.filter(Boolean)
		.join("\n");
}
