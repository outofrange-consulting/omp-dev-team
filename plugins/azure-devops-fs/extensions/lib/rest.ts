// Azure DevOps REST client (PAT auth). API version 7.1.
//
// Auth: Authorization: Basic base64(":" + PAT). PAT from AZURE_DEVOPS_PAT (or
// AZURE_DEVOPS_EXT_PAT / SYSTEM_ACCESSTOKEN). Org/project default from
// AZURE_DEVOPS_ORG / AZURE_DEVOPS_PROJECT but can be overridden per call.

const API = "7.1";

export interface AdoEnv {
	org: string;
	project: string;
	pat: string;
}

export class AdoError extends Error {}

export function resolveEnv(over: { org?: string; project?: string } = {}): AdoEnv {
	const org = over.org ?? process.env.AZURE_DEVOPS_ORG ?? "";
	const project = over.project ?? process.env.AZURE_DEVOPS_PROJECT ?? "";
	const pat =
		process.env.AZURE_DEVOPS_PAT ??
		process.env.AZURE_DEVOPS_EXT_PAT ??
		process.env.SYSTEM_ACCESSTOKEN ??
		"";
	if (!org)
		throw new AdoError("AZURE_DEVOPS_ORG is not set (and no org passed). Set it to your org name.");
	if (!pat)
		throw new AdoError(
			"AZURE_DEVOPS_PAT is not set. Create a PAT (Code: Read/Write, PR: Read/Write, Build: Read) and export it.",
		);
	return { org, project, pat };
}

export function authHeader(pat: string): string {
	return `Basic ${Buffer.from(`:${pat}`).toString("base64")}`;
}

type Query = Record<string, string | number | boolean | undefined>;

function buildUrl(base: string, path: string, query: Query, apiVersion = API): string {
	const u = new URL(base.replace(/\/$/, "") + path);
	u.searchParams.set("api-version", apiVersion);
	for (const [k, v] of Object.entries(query)) {
		if (v !== undefined) u.searchParams.set(k, String(v));
	}
	return u.toString();
}

export interface AdoClient {
	env: AdoEnv;
	orgBase: string;
	projBase: string;
	get<T = unknown>(path: string, query?: Query, opts?: ReqOpts): Promise<T>;
	/** GET that also returns the x-ms-continuationtoken header (for paging). */
	getH<T = unknown>(path: string, query?: Query, opts?: ReqOpts): Promise<{ data: T; continuation?: string }>;
	/** Page a continuation-token list endpoint (builds, commits, …). */
	listToken<T = unknown>(path: string, query?: Query, opts?: ReqOpts & { cap?: number }): Promise<T[]>;
	/** Page a $top/$skip list endpoint. `key` defaults to "value" (use "changeEntries" for PR iteration changes). */
	listSkip<T = unknown>(path: string, query?: Query, opts?: ReqOpts & { key?: string; top?: number; cap?: number }): Promise<T[]>;
	send<T = unknown>(method: string, path: string, body: unknown, query?: Query, opts?: ReqOpts & { contentType?: string }): Promise<T>;
	selfId(): Promise<{ id: string; displayName: string }>;
	/** Resolve a project GUID (needed for policy-evaluation artifactIds). */
	projectId(project?: string): Promise<string>;
}

interface ReqOpts {
	org?: boolean;
	raw?: boolean;
	apiVersion?: string;
}

export function makeClient(env: AdoEnv, signal?: AbortSignal): AdoClient {
	const orgBase = `https://dev.azure.com/${encodeURIComponent(env.org)}`;
	const projBase = `${orgBase}/${encodeURIComponent(env.project)}`;
	const headers = { Authorization: authHeader(env.pat), Accept: "application/json" };

	async function request(
		method: string,
		url: string,
		body?: unknown,
		contentType = "application/json",
		raw = false,
	): Promise<{ data: unknown; headers: Headers }> {
		const init: RequestInit = { method, headers: { ...headers }, signal };
		if (body !== undefined) {
			(init.headers as Record<string, string>)["Content-Type"] = contentType;
			init.body = typeof body === "string" ? body : JSON.stringify(body);
		}
		const res = await fetch(url, init);
		const text = await res.text();
		// ADO returns an HTML sign-in page (200/203) when the PAT is bad.
		if (text.startsWith("<!DOCTYPE html") || res.status === 203) {
			throw new AdoError("Azure DevOps auth failed (got a sign-in page). Check AZURE_DEVOPS_PAT scopes/expiry.");
		}
		if (!res.ok) {
			let msg = `${method} ${url} -> ${res.status}`;
			try {
				const j = JSON.parse(text);
				if (j.message) msg = j.message;
			} catch {
				if (text) msg += `: ${text.slice(0, 300)}`;
			}
			throw new AdoError(msg);
		}
		if (raw) return { data: text, headers: res.headers };
		return { data: text ? JSON.parse(text) : {}, headers: res.headers };
	}

	let projectGuid: string | undefined;

	const client: AdoClient = {
		env,
		orgBase,
		projBase,
		async get(path, query = {}, opts = {}) {
			const base = opts.org ? orgBase : projBase;
			const { data } = await request("GET", buildUrl(base, path, query, opts.apiVersion), undefined, "application/json", opts.raw);
			return data as never;
		},
		async getH(path, query = {}, opts = {}) {
			const base = opts.org ? orgBase : projBase;
			const { data, headers: h } = await request("GET", buildUrl(base, path, query, opts.apiVersion), undefined, "application/json", opts.raw);
			return { data: data as never, continuation: h.get("x-ms-continuationtoken") ?? undefined };
		},
		async listToken(path, query = {}, opts = {}) {
			const cap = opts.cap ?? 1000;
			const out: unknown[] = [];
			let token: string | undefined;
			do {
				const { data, continuation } = await this.getH<{ value?: unknown[] }>(
					path,
					{ ...query, ...(token ? { continuationToken: token } : {}) },
					opts,
				);
				out.push(...(data.value ?? []));
				token = continuation;
			} while (token && out.length < cap);
			return out as never;
		},
		async listSkip(path, query = {}, opts = {}) {
			const key = opts.key ?? "value";
			const top = opts.top ?? 500;
			const cap = opts.cap ?? 2000;
			const out: unknown[] = [];
			let skip = 0;
			for (;;) {
				const data = await this.get<Record<string, unknown[]>>(path, { ...query, $top: top, $skip: skip }, opts);
				const batch = (data[key] ?? []) as unknown[];
				out.push(...batch);
				if (batch.length < top || out.length >= cap) break;
				skip += top;
			}
			return out as never;
		},
		async send(method, path, body, query = {}, opts = {}) {
			const base = opts.org ? orgBase : projBase;
			const { data } = await request(method, buildUrl(base, path, query, opts.apiVersion), body, opts.contentType ?? "application/json");
			return data as never;
		},
		async selfId() {
			const { data } = await request("GET", `${orgBase}/_apis/connectionData?api-version=${API}`);
			const u = (data as { authenticatedUser?: { id: string; providerDisplayName?: string; customDisplayName?: string } }).authenticatedUser;
			if (!u?.id) throw new AdoError("could not resolve authenticated user id");
			return { id: u.id, displayName: u.customDisplayName ?? u.providerDisplayName ?? u.id };
		},
		async projectId(project) {
			if (projectGuid && !project) return projectGuid;
			const name = project ?? env.project;
			const p = await this.get<{ id: string }>(`/_apis/projects/${encodeURIComponent(name)}`, {}, { org: true });
			if (!p?.id) throw new AdoError(`could not resolve project GUID for '${name}'`);
			if (!project) projectGuid = p.id;
			return p.id;
		},
	};
	return client;
}

export { API };
