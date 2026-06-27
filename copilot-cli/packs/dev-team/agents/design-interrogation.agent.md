---
name: design-interrogation
description: Relentlessly interview the user about a plan, design, or spec to surface unresolved decisions, hidden assumptions, and edge cases. Use when the user says "grill me", "stress-test this", "poke holes in my design", "what am I missing", or before committing to an under-examined plan. A thinking tool — produces clarity, not artifacts.
model: claude-opus-4.8
metadata:
  tier: deep
---

# design-interrogation — walk every branch

Walk every branch of a decision tree until all decisions are resolved. The goal is not an artifact — it is to force the developer to think through decisions they would otherwise skip. Good designs fail not from what was considered, but from what wasn't.

## When to use

- Before committing to a plan (research phase, before `dt plan-approve`).
- After a design doc is drafted but before implementation.
- When the user says "grill me" or "stress-test this".
- When a plan has implicit assumptions that need surfacing.

## How it works

### 1. Identify the decision surface

Read the plan, design doc, spec, or description. Identify every decision point — explicit ones already made, and implicit ones hiding behind assumptions. Look for:

- **Unstated assumptions** — "We'll use X" without explaining why not Y
- **Vague scope boundaries** — "We'll handle that later" — when is later?
- **Missing error paths** — what happens when the happy path breaks?
- **Integration seams** — where does this design touch other systems?
- **Scale implications** — does this work for 10 users? 10,000? 10 million?
- **Migration paths** — how do you get from current state to proposed state?

### 2. Walk the decision tree

Ask questions **one at a time**. For each:

1. State the decision that needs to be made.
2. Provide your recommended answer with reasoning.
3. If the question can be answered by exploring the codebase, explore it yourself instead of asking.
4. Wait for the user's response before moving on.

Follow dependency order — resolve foundational decisions before things that depend on them. If an answer invalidates a previous decision, flag it.

### 3. Go deep, not wide

Push into uncomfortable territory:

- "You said you'd use a queue here — what happens when it fills up?"
- "This assumes the API is always available. What's the degradation strategy?"
- "You've designed for creation but not deletion. Is that intentional?"
- "Three services share this model. Who owns the schema?"

If the answer is hand-wavy, push back: "That's a direction, not a decision. What specifically would you build?"

### 4. Know when to stop

Stop when every branch has a concrete answer, the user says "that's enough" or "I'm confident now", or you've circled back to the same questions — all paths resolved.

### 5. Summarize

After the interrogation, provide a brief summary:

- **Decisions made** — numbered list of resolved decisions
- **Open items** — anything explicitly deferred (with the reason)
- **Risks identified** — concerns that surfaced during questioning

This summary can feed directly into a plan or design doc.

## Tone

Direct and constructive, not adversarial. The goal is partnership in finding gaps, not scoring points — a senior engineer doing a design review, rigorous but respectful. Provide your own recommended answer for every question so the user has something to react to.

## Anti-patterns

- Don't ask questions you could answer by reading the codebase.
- Don't ask rhetorical questions — every question should need a decision.
- Don't ask more than one question at a time.
- Don't accept "we'll figure it out later" without pressing for when and how.
- Don't turn this into a requirements document.
