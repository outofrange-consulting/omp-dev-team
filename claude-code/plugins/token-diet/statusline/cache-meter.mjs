#!/usr/bin/env node
// cache-meter.mjs — token-diet live cost/cache statusline for Claude Code.
// Port of OMP's cache-meter extension. Claude Code feeds the statusLine command
// a JSON blob on stdin and renders whatever single line we print to stdout.
// Field names have shifted across CC versions, so read defensively.
//
// Wire it up in ~/.claude/settings.json (the installer does this):
//   "statusLine": { "type": "command",
//     "command": "node \"<plugin>/statusline/cache-meter.mjs\"" }
import { readFileSync } from "node:fs";

let d = {};
try { d = JSON.parse(readFileSync(0, "utf8") || "{}"); } catch {}

const pick = (...paths) => {
  for (const p of paths) {
    let v = d;
    for (const k of p.split(".")) v = v == null ? undefined : v[k];
    if (v !== undefined && v !== null) return v;
  }
  return undefined;
};

const model = pick("model.display_name", "model.id", "model") ?? "?";
const cost = pick("cost.total_cost_usd", "cost.total_usd", "total_cost_usd", "cost");
const ctxUsed = pick("context.used_tokens", "contextWindow.used", "tokens.context", "exceeds_200k_tokens");
const ctxMax = pick("context.max_tokens", "contextWindow.max");
const cacheRead = pick("cost.cache_read_tokens", "tokens.cache_read", "usage.cache_read_input_tokens");
const inputTok = pick("cost.input_tokens", "tokens.input", "usage.input_tokens");
const added = pick("cost.total_lines_added", "lines.added");
const removed = pick("cost.total_lines_removed", "lines.removed");

const parts = [`td ${model}`];
if (typeof cost === "number") parts.push(`$${cost.toFixed(2)}`);
if (typeof ctxUsed === "number" && typeof ctxMax === "number" && ctxMax > 0)
  parts.push(`ctx ${Math.round((ctxUsed / ctxMax) * 100)}%`);
if (typeof cacheRead === "number" && typeof inputTok === "number" && inputTok + cacheRead > 0)
  parts.push(`cache ${Math.round((cacheRead / (inputTok + cacheRead)) * 100)}%`);
if (typeof added === "number" || typeof removed === "number")
  parts.push(`+${added || 0}/-${removed || 0}`);

process.stdout.write(parts.join("  "));
