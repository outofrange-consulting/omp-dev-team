// Deep-merge a patch JSON into a target JSON file, PRESERVING existing target
// values. Only keys ABSENT in the target are filled in from the patch; anything
// the user already set is kept verbatim. Used by the installers to merge
// ~/.omp/agent/mcp.json and ~/.omp/agent/models.yml-adjacent JSON without ever
// clobbering a value the user configured.
//
// Usage: node scripts/merge-json.mjs <target.json> <patch.json>
//   - target is created (with its parent dirs) if missing.
//   - objects merge key-by-key; if a key exists in target it wins (recursing
//     into nested objects). Scalars are kept as-is when the target already has
//     them, otherwise taken from the patch.
//   - arrays are UNION-merged with identity dedupe: all target entries are kept,
//     and patch entries are appended only when absent. Identity is `name`/`id`
//     for objects that have one (so duplicate MCP servers / roles collapse even
//     across key-order differences), else canonicalized (sorted-key) JSON.
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

// Canonical, key-order-independent JSON for dedupe: recursively sort object keys
// so {a:1,b:2} and {b:2,a:1} stringify identically.
function canon(v) {
  if (Array.isArray(v)) return `[${v.map(canon).join(",")}]`;
  if (isObj(v)) {
    return `{${Object.keys(v)
      .sort()
      .map((k) => `${JSON.stringify(k)}:${canon(v[k])}`)
      .join(",")}}`;
  }
  return JSON.stringify(v);
}

// Identity of an array element for dedupe purposes. Objects with a stable
// identity key (`name` or `id`) dedupe on that key (so two MCP servers / roles
// with the same name but different key order or differing details are treated as
// the SAME entry — target wins). Everything else dedupes on canonicalized JSON,
// so key-order-only differences also collapse.
function identity(v) {
  if (isObj(v)) {
    if (typeof v.name === "string") return `name:${v.name}`;
    if (typeof v.id === "string" || typeof v.id === "number") return `id:${v.id}`;
  }
  return `canon:${canon(v)}`;
}

// Merge arrays: keep all target entries (target wins), then append only those
// patch entries whose identity isn't already present in the target.
function mergeArray(d, s) {
  const seen = new Set(d.map(identity));
  for (const item of s) {
    const key = identity(item);
    if (!seen.has(key)) {
      d.push(item);
      seen.add(key);
    }
  }
  return d;
}

function merge(d, s) {
  if (Array.isArray(d) && Array.isArray(s)) return mergeArray(d, s); // identity-dedupe
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
