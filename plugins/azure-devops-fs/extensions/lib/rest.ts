// Shared Azure DevOps auth/env types.
//
// The `ado` tool drives everything through the Azure CLI (`az` + the
// `azure-devops` extension) — see lib/az.ts. The former raw-fetch REST transport
// (makeClient/listToken/listSkip/selfId/resolveEnv) was unused and has been
// removed. Only the pieces still consumed elsewhere remain here:
//   - AdoEnv  (env shape: org/project/pat)
//   - AdoError (typed error)
//   - authHeader (Basic base64(":" + PAT); used by worktree git auth + Code Search)
//
// PAT from AZURE_DEVOPS_PAT (or AZURE_DEVOPS_EXT_PAT / SYSTEM_ACCESSTOKEN).

export interface AdoEnv {
	org: string;
	project: string;
	pat: string;
}

export class AdoError extends Error {}

export function authHeader(pat: string): string {
	return `Basic ${Buffer.from(`:${pat}`).toString("base64")}`;
}
