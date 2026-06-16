// Azure CLI (`az devops`) transport for the `ado` tool.
//
// Instead of raw fetch() REST, we drive the Azure CLI + the `azure-devops`
// extension. The CLI inherits the OS certificate store and proxy settings, so it
// works behind corporate TLS-intercepting proxies (Zscaler / Trend Micro under
// WSL) where a bare fetch would fail. Auth is the PAT: we export it as
// AZURE_DEVOPS_EXT_PAT for the child process, so no interactive `az devops login`
// is required at runtime (the installer still logs in for convenience).
//
// High-level commands (`az repos`, `az pipelines`, `az boards`) are used where
// they exist — they return the same REST JSON the formatters already expect, and
// resolve the current user themselves (so we never need the user GUID). The few
// endpoints without a high-level command (file items, PR iterations/changes,
// threads, statuses, policy evaluations, build logs) go through the generic
// `az devops invoke`.

import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { AdoError, type AdoEnv } from "./rest.ts";

const API = "7.1";

/* eslint-disable @typescript-eslint/no-explicit-any */

function azError(e: any): string {
	if (e?.code === "ENOENT")
		return "Azure CLI 'az' not found. Install it and the azure-devops extension (run the azure-devops-fs installer, or: az extension add --name azure-devops).";
	const err = String(e?.stderr ?? e?.stdout ?? e?.message ?? e).trim();
	if (/is not in the .*extension|not recognized|az devops/i.test(err) && /extension/i.test(err))
		return `${err}\nHint: az extension add --name azure-devops`;
	if (/TF400813|not authorized|Authentication|unauthorized|401/i.test(err))
		return `${err}\nHint: set AZURE_DEVOPS_PAT (Code R/W, PR R/W, Build R, Policy R) or run: az devops login`;
	return err || "az command failed";
}

export interface AzInvokeOpts {
	area: string;
	resource: string;
	route?: Record<string, string | number | undefined>;
	query?: Record<string, string | number | boolean | undefined>;
	method?: string;
	body?: unknown;
	apiVersion?: string;
	raw?: boolean;
}

export interface AzClient {
	env: AdoEnv;
	orgUrl: string;
	/** Run an `az ...` subcommand, parse JSON stdout. Appends --organization (+ --project unless project:false). */
	cli<T = any>(args: string[], opts?: { project?: boolean }): T;
	/** Like cli() but returns raw stdout text. */
	cliText(args: string[], opts?: { project?: boolean }): string;
	/** Generic `az devops invoke` for endpoints without a high-level command. */
	invoke<T = any>(opts: AzInvokeOpts): T;
	/** Project GUID (for policy-evaluation artifactIds). */
	projectId(): string;
}

export function makeAz(env: AdoEnv, signal?: AbortSignal): AzClient {
	// Accept either a bare org name ("contoso") or a full URL.
	const orgUrl = /^https?:\/\//.test(env.org)
		? env.org.replace(/\/+$/, "")
		: `https://dev.azure.com/${encodeURIComponent(env.org)}`;
	const orgFlag = ["--organization", orgUrl];
	const projFlag = env.project ? ["--project", env.project] : [];
	// PAT auth for the azure-devops extension, non-interactive. Only set it when
	// we actually have a PAT — otherwise fall back to a prior `az devops login`.
	const childEnv: NodeJS.ProcessEnv = { ...process.env };
	if (env.pat) childEnv.AZURE_DEVOPS_EXT_PAT = env.pat;

	function exec(args: string[], raw = false): any {
		const full = [...args, "--only-show-errors", ...(raw ? [] : ["--output", "json"])];
		let out: string;
		try {
			out = execFileSync("az", full, {
				encoding: "utf8",
				env: childEnv,
				maxBuffer: 1 << 26, // 64 MB (large diffs/logs)
				signal,
			});
		} catch (e) {
			throw new AdoError(azError(e));
		}
		if (raw) return out;
		const t = out.trim();
		return t ? JSON.parse(t) : null;
	}

	let projectGuid: string | undefined;

	return {
		env,
		orgUrl,
		cli(args, opts = {}) {
			const p = opts.project === false ? [] : projFlag;
			return exec([...args, ...orgFlag, ...p]);
		},
		cliText(args, opts = {}) {
			const p = opts.project === false ? [] : projFlag;
			return exec([...args, ...orgFlag, ...p], true);
		},
		invoke({ area, resource, route = {}, query = {}, method = "GET", body, apiVersion = API, raw = false }) {
			const r: Record<string, string | number | undefined> = { ...(env.project ? { project: env.project } : {}), ...route };
			const args = [
				"devops", "invoke",
				"--area", area, "--resource", resource,
				"--api-version", apiVersion,
				"--http-method", method,
				...orgFlag,
			];
			const rp = Object.entries(r).filter(([, v]) => v !== undefined && v !== "").map(([k, v]) => `${k}=${v}`);
			if (rp.length) args.push("--route-parameters", ...rp);
			const qp = Object.entries(query).filter(([, v]) => v !== undefined && v !== "").map(([k, v]) => `${k}=${v}`);
			if (qp.length) args.push("--query-parameters", ...qp);
			if (body !== undefined) {
				const dir = mkdtempSync(join(tmpdir(), "ado-az-"));
				const f = join(dir, "body.json");
				writeFileSync(f, typeof body === "string" ? body : JSON.stringify(body));
				args.push("--in-file", f, "--media-type", "application/json");
			}
			return exec(args, raw);
		},
		projectId() {
			if (projectGuid) return projectGuid;
			if (!env.project) throw new AdoError("project is required for policy gates (set AZURE_DEVOPS_PROJECT)");
			const p = this.cli<{ id: string }>(["devops", "project", "show", "--project", env.project], { project: false });
			if (!p?.id) throw new AdoError(`could not resolve project GUID for '${env.project}'`);
			projectGuid = p.id;
			return projectGuid;
		},
	};
}

// org required; project optional; PAT optional (a prior `az devops login` can
// provide auth instead). Mirrors resolveEnv but does not force a PAT.
export function resolveAzEnv(over: { org?: string; project?: string } = {}): AdoEnv {
	const org = over.org ?? process.env.AZURE_DEVOPS_ORG ?? "";
	const project = over.project ?? process.env.AZURE_DEVOPS_PROJECT ?? "";
	const pat = process.env.AZURE_DEVOPS_PAT ?? process.env.AZURE_DEVOPS_EXT_PAT ?? process.env.SYSTEM_ACCESSTOKEN ?? "";
	if (!org) throw new AdoError("AZURE_DEVOPS_ORG is not set (and no org passed). Set it to your org name.");
	return { org, project, pat };
}

export { API };
