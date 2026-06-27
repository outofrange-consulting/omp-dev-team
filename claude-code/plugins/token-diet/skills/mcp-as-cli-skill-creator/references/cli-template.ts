#!/usr/bin/env bun
// cli-template.ts — starting skeleton for mcp-as-cli-skill-creator.
//
// A thin one-shot CLI over a stdio MCP server: it spawns the server, does the
// JSON-RPC handshake, calls one tool, prints compact JSON, exits. The generator
// fills in SERVER_CMD, the tool list, and per-subcommand flag mapping. Keep
// credentials in env vars (read here), never hard-coded.
//
// Usage after generation:  <tool> <subcommand> --flag value …   |   <tool> --help

import { spawn } from "node:child_process";

// --- generator fills these in ------------------------------------------------
const SERVER_CMD = process.env.MCP_CLI_SERVER_CMD ?? ""; // e.g. "uvx some-mcp-server"
// name -> { description, required flags } ; documented in the companion skill.
const TOOLS: Record<string, { description: string; required: string[] }> = {
	// example_op: { description: "…", required: ["id"] },
};
// -----------------------------------------------------------------------------

function parseArgs(argv: string[]): { sub?: string; args: Record<string, string> } {
	const [sub, ...rest] = argv;
	const args: Record<string, string> = {};
	for (let i = 0; i < rest.length; i++) {
		const t = rest[i];
		if (t.startsWith("--")) {
			const key = t.slice(2);
			const next = rest[i + 1];
			if (next === undefined || next.startsWith("--")) args[key] = "true";
			else { args[key] = next; i++; }
		}
	}
	return { sub, args };
}

function printHelp(): void {
	console.error("Subcommands (schema lives in the companion skill, not the system prompt):");
	for (const [name, t] of Object.entries(TOOLS)) {
		const flags = t.required.map((f) => `--${f} <v>`).join(" ");
		console.error(`  ${name} ${flags}\t${t.description}`);
	}
}

// One-shot JSON-RPC over the server's stdio: initialize → tools/call → read result.
async function callTool(name: string, params: Record<string, unknown>): Promise<unknown> {
	if (!SERVER_CMD) throw new Error("MCP_CLI_SERVER_CMD is unset");
	const [cmd, ...cmdArgs] = SERVER_CMD.split(" ");
	const child = spawn(cmd, cmdArgs, { stdio: ["pipe", "pipe", "inherit"] });
	const frames = [
		{ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "mcp-cli", version: "0" } } },
		{ jsonrpc: "2.0", method: "notifications/initialized" },
		{ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name, arguments: params } },
	];
	for (const f of frames) child.stdin.write(`${JSON.stringify(f)}\n`);
	child.stdin.end();

	let buf = "";
	for await (const chunk of child.stdout) buf += chunk;
	// Return the result for id:2 (the tools/call response).
	for (const line of buf.split("\n")) {
		if (!line.trim()) continue;
		try {
			const msg = JSON.parse(line);
			if (msg.id === 2) {
				if (msg.error) throw new Error(JSON.stringify(msg.error));
				return msg.result;
			}
		} catch {
			/* skip non-JSON / partial lines */
		}
	}
	throw new Error("no tools/call response from server");
}

const { sub, args } = parseArgs(process.argv.slice(2));
if (!sub || sub === "--help" || sub === "help" || !TOOLS[sub]) {
	printHelp();
	process.exit(sub && sub !== "--help" && sub !== "help" ? 2 : 0);
}
const missing = TOOLS[sub].required.filter((f) => !(f in args));
if (missing.length) {
	console.error(`missing required flag(s): ${missing.map((f) => `--${f}`).join(", ")}`);
	process.exit(2);
}
try {
	const result = await callTool(sub, args);
	console.log(JSON.stringify(result)); // compact; ctx-wire trims further if filtered
} catch (e) {
	console.error(`error: ${(e as Error).message}`);
	process.exit(1);
}
