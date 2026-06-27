---
name: mcp-as-cli-skill-creator
description: >-
  Turn an MCP server (or OpenAPI / GraphQL endpoint) into a thin runtime CLI plus
  a companion skill, so the tool's JSON schema stays OUT of the model's context
  window — the agent calls the CLI via bash on demand instead of paying for N MCP
  tool schemas every request. Use when the user says "wrap this MCP as a CLI",
  "CLI-over-MCP", "keep the MCP schema out of context", "make a skill for this
  API", or wants to trim tool-schema startup cost. This is the ctx7/acli pattern,
  generalized.
user-invocable: true
allowed-tools: read, write, bash
---

# mcp-as-cli-skill-creator — schema out of context, capability in a CLI

OMP inlines every loaded tool's JSON schema into the system prompt on **every**
request. A chatty MCP server (10–40 tools) can cost thousands of startup tokens
you pay for whether or not you call it. token-diet already dodges this for the
tools it cares about by running them as **CLIs** — `ctx7` (context7) and `acli`
(Atlassian) are bash CLIs, *not* MCP processes, so their schema never enters the
window; the agent invokes them on demand and ctx-wire compresses the output.

This skill **generalizes that move**: given any MCP server / OpenAPI spec /
GraphQL endpoint, it generates (1) a thin **CLI wrapper** that exposes each
operation as a subcommand, and (2) a companion **skill doc** that teaches the
agent how to call it. The capability stays fully available; only the schema
leaves the hot path (it lives in the skill, loaded on demand, not in the system
prompt).

## When to use it / when NOT to

Use it when a server is **schema-heavy but call-light** — many tools, used
occasionally (the worst case for always-loaded schemas). Good fits: read-heavy
data/query servers, niche admin APIs, anything you reach for a few times a session.

Do **not** wrap:
- Servers whose tools are on the hot path every turn (the schema earns its place).
- Streaming / long-lived / stateful-session tools (a one-shot CLI call can't model them).
- Tools that need interactive approval UIs mid-call.

If unsure, measure first: with `discoveryMode: all` (token-diet default) OMP
already hides non-essential tool schemas behind on-demand discovery — check
whether the server is actually costing you before wrapping it.

## Inputs

Ask for / detect the source, then its auth:
- **MCP server** — a stdio command (`cmd args…`) or an HTTP URL, plus any env/token.
- **OpenAPI** — a spec URL or file (`openapi.json` / `.yaml`).
- **GraphQL** — an endpoint URL (introspection) + auth header.

Pick a short **tool name** (the CLI binary name, e.g. `foo`).

## Steps

1. **Enumerate operations.**
   - MCP (stdio): start the server and call `tools/list` over JSON-RPC, e.g.
     ```bash
     printf '%s\n' \
       '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"cli-gen","version":"0"}}}' \
       '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
       '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
       | <server-cmd>     # capture stdout, parse the tools/list result
     ```
   - MCP (http): POST the same JSON-RPC frames to the URL.
   - OpenAPI: read `paths` → each `(method, path, operationId, params, requestBody)`.
   - GraphQL: run the standard introspection query; treat top-level
     `Query`/`Mutation` fields as operations.
   Record, per operation: name, one-line description, and its parameters
   (name, type, required).

2. **Generate the CLI wrapper.** Write one executable to `~/.local/bin/<tool>`
   (first on PATH, inherited by OMP's bash; same place ctx-wire/acli live). One
   subcommand per operation; flags map to parameters; it performs the MCP
   `tools/call` (or the HTTP request) and prints **compact JSON** to stdout.
   Use the `references/cli-template.ts` skeleton as the starting point — it
   handles arg parsing, the JSON-RPC handshake, `--help`, and JSON output.
   Make it executable (`chmod +x`). Keep credentials in **env vars**, never baked
   into the script.

3. **Generate the companion skill.** Write `skills/<tool>/SKILL.md` documenting:
   the one-line purpose, the auth env vars, and a table of `‹tool› ‹subcommand›
   --flags` with each operation's description. This doc is what the agent reads
   (on demand) instead of the MCP schema. Keep it tight — it is the schema's
   replacement, so list every operation but no more.

4. **Keep it OUT of `.mcp.json`.** That is the entire point: do **not** register
   the server as MCP. If it was registered, disable that entry. The CLI + skill
   replace it.

5. **(Optional) Compress the output.** If the CLI is verbose, add a
   `ctx-wire/filters.d/<tool>.toml` filter (and redact any token patterns), so
   its output is trimmed before it hits context — same as `acli.toml`.

6. **Verify.** Run `<tool> --help` and one real subcommand; confirm JSON comes
   back and (for MCP) the server is no longer needed in `.mcp.json`.

## Output

- `~/.local/bin/<tool>` — the runtime CLI (on PATH).
- `skills/<tool>/SKILL.md` — the on-demand usage doc (schema replacement).
- optional `ctx-wire/filters.d/<tool>.toml` — output compaction.

Net effect: the server's schema leaves the system prompt; the capability stays a
bash call away. Exactly how `ctx7` and `acli` already work in this plugin.

## Guardrails

- Lazy ≠ lossy: list **every** operation in the skill doc — don't silently drop
  ones you couldn't parse; note them so the user knows the CLI is partial.
- Secrets only via env; never write tokens into the CLI or the skill doc.
- One-shot semantics only — flag any streaming/stateful tool you skip.
