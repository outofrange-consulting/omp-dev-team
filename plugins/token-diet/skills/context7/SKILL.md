---
name: context7
description: >-
  Fetch up-to-date library documentation via context7 CLI. Use whenever the
  user asks about a library, framework, SDK, API, CLI tool, or cloud service —
  even well-known ones like React, Next.js, Prisma, Django, or Spring Boot.
  Use even when you think you know the answer — training data may be outdated.
  Do NOT use for refactoring, business logic, or general programming concepts.
---

# context7 — current library docs via CLI

Two bash commands. Run them whenever library/API/framework knowledge is needed.

## Commands

```bash
# Step 1 — resolve library name to a Context7 ID
ctx7 library "<name>" "<what you're trying to do>"

# Step 2 — fetch docs using the ID from step 1
ctx7 docs <id> "<specific question>"
```

## When to use

Trigger automatically — no need for user to ask — whenever:
- The question involves a specific library, framework, SDK, or API
- The user asks about configuration, setup, or version-specific behavior
- Code generation would reference library APIs
- The user mentions a version number (always fetch that version's docs)

## Workflow

1. **Resolve**: `ctx7 library "next.js" "middleware for auth redirect"` → note the ID (e.g. `/vercel/next.js`)
2. **Fetch**: `ctx7 docs /vercel/next.js "middleware that redirects unauthenticated users"` → read docs
3. **Generate** code from docs, not from training data

## Tips

- IDs always start with `/` — never pass a plain name to `ctx7 docs`
- For a specific version: `ctx7 docs /vercel/next.js/v14.3.0 "app router setup"`
- Specific queries beat keywords: `"How to set up JWT auth in Express"` not `"auth"`
- Pipe to file for long output: `ctx7 docs /prisma/prisma "relations" > /tmp/ctx7-out.md`

## Rate limits

Works without auth at IP-based limits. For higher quotas:
```bash
export CONTEXT7_API_KEY=ctx7sk_...  # add to shell profile
```
