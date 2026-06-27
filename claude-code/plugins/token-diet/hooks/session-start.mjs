#!/usr/bin/env node
// token-diet SessionStart hook — inject the token-discipline routing rule as
// always-on context (Claude Code has no rule-glob engine). Rewritten for Claude
// Code idioms (Read/Grep/Glob + the codebase-memory MCP), dropping OMP-native
// references (astGrep/astEdit/discoveryMode).
const rule = `# Token discipline (token-diet)

- **Command output is auto-compressed.** ctx-wire transparently filters noisy
  command output (build/test/lint/git/search) and scrubs secrets *before* it
  reaches context — run commands normally, no prefix or wrapper. Full logs are
  kept on disk; don't re-run a command just to "see everything" (\`ctx-wire gain\`
  shows the savings). If ctx-wire isn't installed, nothing changes.
- **Code structure via the codebase-memory MCP.** When the \`codebase-memory\`
  MCP tools are available, prefer them over Grep/Glob/Read for "who calls X",
  "what does X call", "where is symbol Y", "impact of changing Z", and
  architecture questions — one graph query replaces dozens of grep+read
  round-trips. Reserve full-file Read for when you actually need to read or edit
  prose/implementation.
- **Don't re-read unchanged files.** If a file is already in context and hasn't
  changed, reuse it instead of reading it again. Don't paste or echo the same
  large output twice.
- **Edit narrowly.** Prefer targeted Edit over Read-whole-file → Write-whole-file;
  on large files the full rewrite is the dominant token cost.
- **Be terse on request.** The /token-diet:caveman skill compresses output; the
  /token-diet:yagni skill keeps diffs minimal. Use them when the user asks to
  save tokens or keep it simple.`;

process.stdout.write(JSON.stringify({
  hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: rule },
}));
