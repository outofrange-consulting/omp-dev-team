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
			"AZURE_DEVOPS_PAT is not set. Create a PAT (Code: Read/Write, PR: Read/Write) and export it.",
		);
	return { org, project, pat };
}

export function authHeader(pat: string): string {
	return `Basic ${Buffer.from(`:${pat}`).toString("base64")}`;
}

function buildUrl(
	base: string,
	path: string,
	query: Record<string, string | number | boolean | undefined>,
): string {
	const u = new URL(base.replace(/\/$/, "") + path);
	u.searchParams.set("api-version", API);
	for (const [k, v] of Object.entries(query)) {
		if (v !== undefined) u.searchParams.set(k, String(v));
	}
	return u.toString();
}

export interface AdoClient {
	env: AdoEnv;
	/** dev.azure.com/{org} base */
	orgBase: string;
	/** dev.azure.com/{org}/{project} base */
	projBase: string;
	get<T = unknown>(path: string, query?: Record<string, string | number | boolean | undefined>, opts?: { org?: boolean; raw?: boolean }): Promise<T>;
	send<T = unknown>(method: string, path: string, body: unknown, query?: Record<string, string | number | boolean | undefined>, opts?: { org?: boolean; contentType?: string }): Promise<T>;
	selfId(): Promise<{ id: string; displayName: string }>;
}

export function makeClient(env: AdoEnv, signal?: AbortSignal): AdoClient {
	const orgBase = `https://dev.azure.com/${encodeURIComponent(env.org)}`;
	const projBase = `${orgBase}/${encodeURIComponent(env.project)}`;
	const headers = { Authorization: authHeader(env.pat), Accept: "application/json" };

	async function request(method: string, url: string, body?: unknown, contentType = "application/json", raw = false): Promise<unknown> {
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
		if (raw) return text;
		return text ? JSON.parse(text) : {};
	}

	const client: AdoClient = {
		env,
		orgBase,
		projBase,
		async get(path, query = {}, opts = {}) {
			const base = opts.org ? orgBase : projBase;
			return request("GET", buildUrl(base, path, query), undefined, "application/json", opts.raw) as Promise<never>;
		},
		async send(method, path, body, query = {}, opts = {}) {
			const base = opts.org ? orgBase : projBase;
			return request(method, buildUrl(base, path, query), body, opts.contentType ?? "application/json") as Promise<never>;
		},
		async selfId() {
			const data = (await request("GET", `${orgBase}/_apis/connectionData?api-version=${API}`)) as {
				authenticatedUser?: { id: string; providerDisplayName?: string; customDisplayName?: string };
			};
			const u = data.authenticatedUser;
			if (!u?.id) throw new AdoError("could not resolve authenticated user id");
			return { id: u.id, displayName: u.customDisplayName ?? u.providerDisplayName ?? u.id };
		},
	};
	return client;
}

export { API };
