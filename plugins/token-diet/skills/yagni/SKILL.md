---
name: yagni
description: >-
  Write minimal code — the laziest-senior-dev / YAGNI discipline. Use when the
  user says "yagni", "ponytail", "minimal code", "keep it simple", "don't
  over-engineer", "fewer lines", or asks to review/trim a diff for bloat. Fewer
  lines = fewer tokens over the whole session + less tech debt.
---

# yagni — the laziest senior dev in the room

> The best code is the code you never wrote.

Ported from [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail).
This is the **write-less-code** layer of token-diet (caveman trims prose,
ctx-wire trims command output, CodeGraph reads less, **yagni writes less**).

## The ladder — climb it BEFORE writing code

1. **Does this need to exist at all?** → don't build it (YAGNI: no speculative
   features, options, abstractions, or config "for later").
2. **Standard library does it?** → use it.
3. **Native platform / framework feature?** → use it.
4. **Already-installed dependency does it?** → use it (don't add a new dep).
5. **Can it be one line / one small function?** → make it one.
6. **Only then** write the minimum viable code — and no more.

Prefer **deleting** over adding. Reuse over rewrite. Inline a thing used once.
No new file/class/layer unless it earns its keep. No premature generalization,
no "just in case" params, no dead code, no comments restating the code.

## Lazy, not negligent — never on the chopping block

Minimalism stops at correctness and safety. Always keep:

- trust-boundary / input validation, authn/authz, and other **security**;
- **data-loss** handling (transactions, idempotency, careful migrations);
- error handling at real boundaries; **accessibility**;
- the **tests** for the behavior (and never edit a `.feature`/test to dodge work
  — fix the code; `tdd-guard` enforces this).

## Levels (`/yagni <level>`)

- **off** — normal behavior.
- **lite** — prefer stdlib/existing code; cut obvious over-engineering.
- **full** (default) — the full ladder; one-liners where clear; no speculative
  abstractions or options.
- **ultra** — maximal restraint: delete-first, inline, no new files unless
  strictly required; smallest possible diff.

Stay in the chosen level until told "off"/"normal".

## Review modes (audit existing work)

- **review** a diff/PR for YAGNI violations (speculative code, needless options,
  premature abstraction, copy-paste, dead code) and propose the smaller version.
- **audit** a file/module for the same and report the biggest wins.
- **debt** — list over-engineering that's already in the codebase, ranked by
  lines/complexity removable without losing behavior.

## Why it saves tokens

Less code generated now = fewer output tokens, and a smaller codebase = fewer
input tokens every future turn (less to read, summarize, and reason over).
Upstream benchmarks report ~80–94% less code and large cost/latency cuts; even
modestly, every line you don't write is a line nobody re-reads.
