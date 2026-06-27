# explore

# Explore

Role: worker. This command is a thin entry point: it parses arguments, runs the
charter-quality + reachability pre-flight, then runs the
[`exploratory-testing`](../the /exploratory-testing skill) skill as the
probe loop. It does not probe directly — the skill owns the protocol.

## Worker constraints

1. Probe a **running** target; do not fix anything. Critical defects go to `/triage`.
2. Stop at or before the probe budget; always leave a usable (possibly partial) report.
3. **Be concise.** Stream one line per probe to chat; detail lives in the report.

## Parse Arguments

Arguments: $ARGUMENTS

- `--charter '<goal>'` — **required**. `Explore [target] with [approach] to discover [concern]`.
- `target` — URL/endpoint/command under test (may be implied by the charter).
- `--probe-budget <n>` — default `15`.
- `--invariants '<expr,...>'` — per-probe invariants; a violation is Critical-immediate.
- `--no-adversarial` — skip adversarial expansion (on by default).
- `--force` — proceed past a charter-quality warning.

If `--charter` is absent, do not probe and do not write a report — emit exactly:

```
What should I investigate? Provide a charter: --charter '<goal>'
```

## Steps

1. **Charter quality** — evaluate the charter against the field-guide anti-patterns. On a match, emit a one-line warning and prompt to refine or re-run with `--force`; do not probe until acceptable or forced.
2. **Reachability** — baseline-request the target. If unreachable, report the URL + error and stop (no report).
3. **Run the skill** — invoke `exploratory-testing` with the parsed charter, budget, invariants, and flags. It runs the probe loop, adversarial expansion, defect classification, auto-triage, and writes `reports/explore-<YYYYMMDDThhmmss>.md` incrementally — ending with a "Next Exploration" section of 2–3 follow-up charters.

Surface the report path and any triaged defects in chat. On `/stop`, the skill finalizes a partial report.
