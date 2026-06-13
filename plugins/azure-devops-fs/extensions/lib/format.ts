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

export function fmtPr(pr: any, threads?: any[]): string {
	const lines: string[] = [
		`# !${pr.pullRequestId} ${pr.title}`,
		webUrl(pr) ?? "",
		`Status: ${pr.status}${pr.isDraft ? " (draft)" : ""}  ·  ${(pr.sourceRefName ?? "").replace("refs/heads/", "")} → ${(pr.targetRefName ?? "").replace("refs/heads/", "")}`,
		`Author: ${pr.createdBy?.displayName ?? "?"}  ·  ${pr.creationDate ?? ""}`,
	];
	if (pr.reviewers?.length) {
		lines.push(
			"Reviewers: " +
				pr.reviewers.map((r: any) => `${r.displayName}(${reviewerVote(r.vote ?? 0)})`).join(", "),
		);
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
