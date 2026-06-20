// Deep-merge a patch JSON into a target JSON file, PRESERVING existing target
// values. Only keys ABSENT in the target are filled in from the patch; anything
// the user already set is kept verbatim. Used by the installers to merge
// ~/.omp/agent/mcp.json and ~/.omp/agent/models.yml-adjacent JSON without ever
// clobbering a value the user configured.
//
// Usage: node scripts/merge-json.mjs <target.json> <patch.json>
//   - target is created (with its parent dirs) if missing.
//   - objects merge key-by-key; if a key exists in target it wins (recursing
//     into nested objects). Arrays and scalars are kept as-is when the target
//     already has them, otherwise taken from the patch.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const [target, patch] = process.argv.slice(2);
if (!target || !patch) {
  console.error("usage: merge-json.mjs <target.json> <patch.json>");
  process.exit(2);
}

const readJson = (p, fallback) => {
  if (!existsSync(p)) return fallback;
  const text = readFileSync(p, "utf8").trim();
  if (!text) return fallback;
  return JSON.parse(text);
};

const dst = readJson(target, {});
const src = JSON.parse(readFileSync(patch, "utf8"));

const isObj = (v) => v !== null && typeof v === "object" && !Array.isArray(v);

function merge(d, s) {
  if (!isObj(d) || !isObj(s)) return d === undefined ? s : d; // target wins when set
  for (const k of Object.keys(s)) {
    d[k] = k in d ? merge(d[k], s[k]) : s[k];
  }
  return d;
}

const out = merge(dst, src);
mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, `${JSON.stringify(out, null, 2)}\n`);
console.log(`merged ${patch} -> ${target}`);
