// Parse the ado:// "filesystem" URIs into structured targets.
//
//   ado://{org}/{project}/{repo}/{path...}@{ref}     -> a file or tree
//   ado://{org}/{project}/{repo}                     -> repo root
//   adopr://{org}/{project}/{repo}/{id}              -> a pull request
//   adopr://{org}/{project}/{repo}/{id}/diff[/path]  -> PR diff (all / one file)
//
// org/project may be omitted and filled from env (AZURE_DEVOPS_ORG /
// AZURE_DEVOPS_PROJECT) — then the form is ado://{repo}/{path}@{ref}. We
// disambiguate by counting segments against what env supplies.

export interface RepoTarget {
	kind: "repo";
	org: string;
	project: string;
	repo: string;
	path: string; // "/" for root
	ref?: string;
}

export interface PrTarget {
	kind: "pr";
	org: string;
	project: string;
	repo: string;
	id: number;
	diff?: { path?: string; all: boolean };
}

export type AdoTarget = RepoTarget | PrTarget;

export interface Defaults {
	org?: string;
	project?: string;
	repo?: string;
}

function splitRefSuffix(s: string): { body: string; ref?: string } {
	const at = s.lastIndexOf("@");
	if (at === -1) return { body: s };
	return { body: s.slice(0, at), ref: s.slice(at + 1) || undefined };
}

export function parseAdoUri(uri: string, def: Defaults = {}): AdoTarget {
	const m = uri.match(/^(adopr|ado):\/\/(.*)$/);
	if (!m) throw new Error(`Not an ado:// URI: ${uri}`);
	const scheme = m[1];
	const { body, ref } = splitRefSuffix(m[2]);
	const segs = body.split("/").filter((s) => s.length > 0);

	// Fill org/project from defaults when the URI omits them. We require the
	// repo to always be present in the URI; org/project are prepended from env
	// when there aren't enough leading segments.
	const need = scheme === "adopr" ? 1 : 0; // pr needs a trailing id (+ maybe diff)
	const lead: string[] = [];
	const work = [...segs];

	// Heuristic: if the first segment equals the env org, treat it as org.
	// Otherwise, prepend env org/project as needed.
	let org = def.org;
	let project = def.project;
	if (work[0] && def.org && work[0] === def.org) {
		org = work.shift();
		if (work[0] && def.project && work[0] === def.project) project = work.shift();
		else if (work.length >= (scheme === "adopr" ? 2 + need : 2)) project = work.shift();
	} else if (work.length >= (scheme === "adopr" ? 4 : 3)) {
		// Looks fully-qualified: org/project/repo/...
		org = work.shift();
		project = work.shift();
	}
	if (!org) throw new Error(`ado uri: org missing (set AZURE_DEVOPS_ORG or include it): ${uri}`);
	if (!project) throw new Error(`ado uri: project missing (set AZURE_DEVOPS_PROJECT or include it): ${uri}`);

	const repo = work.shift() ?? def.repo;
	if (!repo) throw new Error(`ado uri: repo missing: ${uri}`);

	if (scheme === "adopr") {
		// remaining: <id> [diff [path...]]
		const idStr = work.shift();
		const id = Number(idStr);
		if (!Number.isFinite(id)) throw new Error(`adopr uri: invalid PR id "${idStr}": ${uri}`);
		let diff: PrTarget["diff"];
		if (work[0] === "diff") {
			work.shift();
			diff = work.length ? { path: work.join("/"), all: false } : { all: true };
		}
		void lead;
		return { kind: "pr", org, project, repo, id, diff };
	}

	const path = work.length ? `/${work.join("/")}` : "/";
	return { kind: "repo", org, project, repo, path, ref };
}

export function isAdoUri(s: string | undefined): boolean {
	return !!s && /^adopr?:\/\//.test(s);
}
