// SQLite read-cache for ado:// reads, mirroring OMP's github-cache approach.
// Stored at ~/.omp/cache/ado-cache.db. Best-effort: any failure degrades to
// "no cache" rather than throwing.

import { homedir } from "node:os";
import { join } from "node:path";
import { mkdirSync } from "node:fs";

type DB = {
	query: (sql: string) => { get: (...a: unknown[]) => unknown; run: (...a: unknown[]) => unknown };
	run: (sql: string) => void;
};

let db: DB | null | undefined;

function open(): DB | null {
	if (db !== undefined) return db;
	try {
		// bun:sqlite is always available under OMP's Bun runtime.
		const dir = process.env.OMP_ADO_CACHE_DIR ?? join(homedir(), ".omp", "cache");
		mkdirSync(dir, { recursive: true });
		// Dynamic import keeps non-Bun environments (tests) from crashing at load.
		// eslint-disable-next-line @typescript-eslint/no-var-requires
		const { Database } = require("bun:sqlite") as { Database: new (p: string) => DB };
		const d = new Database(join(dir, "ado-cache.db"));
		d.run("CREATE TABLE IF NOT EXISTS cache (k TEXT PRIMARY KEY, v TEXT NOT NULL, ts INTEGER NOT NULL, fp TEXT)");
		db = d;
	} catch {
		db = null;
	}
	return db;
}

function fingerprint(): string {
	const pat = process.env.AZURE_DEVOPS_PAT ?? "";
	// short, non-reversible scope key so cache rows don't leak across creds
	let h = 0;
	for (let i = 0; i < pat.length; i++) h = (h * 31 + pat.charCodeAt(i)) | 0;
	return String(h >>> 0);
}

export function cacheGet(key: string, hardTtlSec: number): string | null {
	if (process.env.OMP_ADO_CACHE === "0") return null;
	const d = open();
	if (!d) return null;
	try {
		const row = d.query("SELECT v, ts, fp FROM cache WHERE k = ?").get(key) as
			| { v: string; ts: number; fp: string }
			| undefined;
		if (!row || row.fp !== fingerprint()) return null;
		if ((Date.now() - row.ts) / 1000 > hardTtlSec) return null;
		return row.v;
	} catch {
		return null;
	}
}

export function cacheSet(key: string, value: string): void {
	if (process.env.OMP_ADO_CACHE === "0") return;
	const d = open();
	if (!d) return;
	try {
		d.query("INSERT OR REPLACE INTO cache (k, v, ts, fp) VALUES (?, ?, ?, ?)").run(
			key,
			value,
			Date.now(),
			fingerprint(),
		);
	} catch {
		/* ignore */
	}
}
