// Validate every *.json in the repo (cross-platform; used by CI).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

let checked = 0;
let bad = 0;
function walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry === ".git") continue;
    const p = join(dir, entry);
    const s = statSync(p);
    if (s.isDirectory()) walk(p);
    else if (entry.endsWith(".json")) {
      checked++;
      try {
        JSON.parse(readFileSync(p, "utf8"));
      } catch (err) {
        bad++;
        console.error(`INVALID  ${p}\n         ${err.message}`);
      }
    }
  }
}

walk(process.cwd());
console.log(`Checked ${checked} JSON files — ${bad} invalid.`);
process.exit(bad ? 1 : 0);
