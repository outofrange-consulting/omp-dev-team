# Legacy Test Strategy

How to decide **where** to write a characterization test and **how** to edit
safely while you have none — by reasoning about *effects* first. Adapted from
*Working Effectively with Legacy Code* (Feathers, ch. 11–13, 23). Complements the
`legacy-code` skill (the change algorithm) and `dependency-breaking-techniques.md`
(the seams).

## 1. Reason about effects

Before writing a test, list everything that — if changed — alters a method's
observable result: its return value, the objects it mutates (by reference), and
the state callers can see. Exclude immutables and pure statics. This toolless,
learnable skill tells you **which methods are worth testing** and what a test
would have to observe.

## 2. Draw an effect sketch

A small directed graph of cause → effect across the change. It reveals:

- **Fan-out** — one input affecting many outputs: test at the richest endpoint.
- **Hidden classes** — clusters that suggest an Extract Class boundary.
- **Simplification feedback** — if the sketch is a hairball, the design is too
  coupled; bias toward more coverage where encapsulation fights you.

## 3. Find interception & pinch points

- **Interception point** — an observable place where you can detect an effect.
- **Pinch point** — a narrow spot where **1–2 methods** detect **many** changes.
  Ideal anchor for characterization tests: maximum coverage, minimal setup.
- Test: *"If I break this method, will I sense it here?"* No pinch point → your
  test scope is too broad; narrow it.

## 4. Write the characterization tests

Document what the code **actually does** (not what it should): call it, let the
assertion fail, read the real output, assert that observed value, repeat until
the behavior is pinned. These tests are a safety net for refactoring, not a spec.

## 5. Edit safely while getting there

| Discipline | Why |
|---|---|
| **Lean on the Compiler** | Make a type change and let compile errors enumerate every call site to fix. |
| **Preserve Signatures** | Copy whole parameter lists rather than retyping — avoids silent transposition bugs in untested code. |
| **Single-Goal Editing** | One intention per edit; don't refactor and add behavior at once. |
| **Hyperaware Editing** | In untested code, treat every keystroke as risky — slow down, re-read. |

## Connections

- The seams to break a dependency → `dependency-breaking-techniques.md`.
- The overall change algorithm → `legacy-code` skill.
- Where these tests run in CI → `database-test-patterns.md`, `cd-test-architecture.md`.
