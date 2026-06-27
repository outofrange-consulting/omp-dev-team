<!-- token-diet:begin -->
# token-diet (GitHub Copilot CLI)

This workspace runs **token-diet**: aggressive, lossless-first context reduction.

## What's active

- **ctx-wire** — transparent shell-output compression + secret scrubbing via PATH
  shims (CLI-agnostic; installed to `~/.local/bin`). Verbose command output
  (build/test/git) is trimmed to its signal before it reaches context, EN+FR.
- **post-tool-use compression hook** — scrubs secrets, collapses blank runs, and
  head/tail-truncates very large *non-shell* tool output. Lossy truncation is
  always marked; untouched output passes through unchanged.
- **codebase-memory-mcp** — query symbols/definitions/call-graph through the MCP
  server **instead of** grepping + reading whole files. Reach for it first when
  you need "where is X defined / who calls Y" — it is far cheaper than reading
  files end to end.

## How to spend tokens well

- **Prefer codebase-memory-mcp over `grep` + full-file reads.** Read files (or
  ranges) only after the symbol query narrows the target.
- **Read ranges, not whole files.** Once you know the line, read around it.
- **Don't re-read what you just wrote or read.** Trust the prior result.
- **caveman output** (terse mode): when the user asks for brevity, answer in
  minimal words — facts and code, no preamble, no restating the question, no
  "I will…". One-sentence wrap-up.
- **yagni**: write the minimal code that satisfies the requirement. No speculative
  abstraction, no options nobody asked for, no dead parameters "for later".

These are defaults, not gags: when a full file read or a longer explanation is
genuinely the right call, do it — and say why.
<!-- token-diet:end -->
