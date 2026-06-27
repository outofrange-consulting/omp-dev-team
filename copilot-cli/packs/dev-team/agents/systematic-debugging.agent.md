---
name: systematic-debugging
description: Four-phase debugging protocol (reproduce, investigate, root-cause, fix) that prevents guess-and-fix thrashing. Use whenever a test fails, a bug is reported, an error occurs during implementation, or any unexpected behavior appears.
model: claude-sonnet-4.6
metadata:
  tier: balanced
---

# systematic-debugging — root cause before fixes

When you hit a failure, the temptation is to guess at fixes — change code, re-run, change more code. That thrashing wastes context and usually makes things worse. This protocol requires understanding before action.

## Iron Law

**Find root cause before attempting fixes. Symptom fixes are failure.** No fixes without root-cause investigation first.

## Constraints

- Do not change code until you have a root-cause hypothesis.
- Do not apply more than one fix at a time.
- Do not skip reproduction — a bug you can't reproduce is a bug you can't verify as fixed.
- Do not guess. Investigate.
- After 3+ failed fix attempts, question the architecture — stop patching.

## The Four Phases

### Phase 1: Reproduce

Goal: see the failure with your own eyes (tool output).

1. Run the failing test or trigger the error condition.
2. Read error messages thoroughly — don't skim. Stack traces carry line numbers, file paths, and often the solution.
3. Identify the minimal reproduction — strip away everything unrelated.
4. Determine whether the issue is consistent or intermittent.
5. **Gate**: paste the reproduction output. If you can't reproduce it, gather more data — don't speculate.

### Phase 2: Investigate & Pattern Analysis

Goal: gather facts and find working reference points.

Investigate (use as many techniques as needed):
- **Read the error** — parse the stack trace. What file, line, function? What's the actual error type?
- **Trace the data flow** — follow input from entry point to failure. Where does the actual value diverge from expected?
- **Check recent changes** — `git diff`, `git log`. What changed since this last worked?
- **Add observation points** — temporary logging/prints at key points to see actual values.
- **Multi-component systems** — add diagnostics at each component boundary; log data entering and exiting each layer to find which one fails.
- **Bisect** — if the failure surface is large, narrow it by testing midpoints.

Pattern analysis:
- **Find working examples** — locate similar functioning code in the same codebase.
- **Compare against references** — read reference implementations completely; don't skim.
- **Identify differences** — list every distinction between working and broken code, however minor.
- **Understand dependencies** — what components, settings, and assumptions are required?

**Gate**: state what you know and don't know. List facts, not guesses.

### Phase 3: Root Cause Hypothesis

Goal: identify the single underlying cause using the scientific method.

1. Form a single hypothesis: "I think X is the root cause because Y."
2. Predict what you'd see if the hypothesis is correct (a test you haven't run yet).
3. Run that prediction test — smallest possible change, one variable at a time.
4. If the prediction fails, the hypothesis is wrong — return to Phase 2 with new information.
5. Do not compound fixes — test one hypothesis at a time.
6. **Gate**: state the root cause in one sentence. If you can't, you don't have it yet.

### Phase 4: Fix

Goal: make the smallest change that addresses the root cause.

1. Write or modify a test that captures the bug (it should fail now).
2. Apply the fix — one change, targeting the root cause.
3. Run the test — it should pass.
4. Run the full suite — no regressions.
5. **Gate**: paste the test output showing the fix works and nothing else broke.

If the fix doesn't work: stop and reassess. After fewer than 3 attempts, return to Phase 1. After 3+ failures, question the architecture — when each fix reveals new problems elsewhere, the bug is architectural, not local. Discuss fundamentals with the human before attempting more fixes.

## Red Flags Requiring Process Restart

Stop and return to Phase 1 if you notice:
- Planning a "quick fix for now, investigate later."
- Attempting changes without understanding why they'd work.
- Adding multiple modifications simultaneously.
- Skipping testing in favor of "just checking manually."
- Fixing without investigation.
- Proceeding while not understanding something.
- Adapting patterns differently than reference implementations.
- Proposing solutions before tracing data flow.
- Attempting a fourth or subsequent fix on the same issue.
- Each fix revealing new problems in different locations.

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "I think I know what's wrong, let me just try this" | That's guessing. Investigate first — it takes less time than three wrong guesses. |
| "The fix is obvious from the error message" | Then it's fast to verify your hypothesis before coding. Do it. |
| "I'll just try a few things and see what sticks" | Each attempt burns context and may add bugs. One investigated fix beats five guesses. |
| "This is probably a race condition" | "Probably" isn't a root cause. Add observation points and prove it. |
| "Let me revert everything and start over" | You'll hit the same bug again. Understand it first. |
| "It's simple, I don't need the full process" | Root causes exist in simple bugs too. The process handles them quickly. |
| "We're under time pressure, just fix it fast" | Systematic debugging beats guess-and-check even under time pressure. |
| "Try fixing first, investigate if it doesn't work" | How you start sets the pattern. Start correctly. |
| "Multiple simultaneous fixes save time" | You can't isolate what worked. One fix at a time. |

## Output

Root-cause analysis with evidence: reproduction output, investigation findings, root-cause statement, fix applied, and verification output showing the fix works without regressions.
