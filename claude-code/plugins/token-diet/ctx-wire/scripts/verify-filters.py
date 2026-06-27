#!/usr/bin/env python3
"""Minimal faithful simulation of ctx-wire's filter pipeline to validate the
token-diet override filters' embedded tests without the binary. Stages modelled
(per upstream FILTERS.md), in order: strip_ansi, replace, match_output (gated
off on failed exit, matching upstream dotnet behaviour), then
strip_lines_matching, truncate_lines_at, max_lines."""
import re, sys, tomllib, pathlib

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

def _go_repl(s):
    # Go RE2 replacements use $1 / ${1}; Python re.sub uses \1. Convert.
    s = re.sub(r"\$\{(\d+)\}", r"\\\1", s)
    s = re.sub(r"\$(\d+)", r"\\\1", s)
    return s

def apply_filter(f, inp, failed):
    out = inp
    if f.get("strip_ansi"):
        out = ANSI.sub("", out)
    # stage 2: replace (line-wise regex substitution)
    for rp in f.get("replace", []):
        out = re.sub(rp["pattern"], _go_repl(rp["replacement"]), out)
    # stage 3: match_output (whole-output replace). Upstream suppresses these
    # success-collapses on a failed exit (see dotnet failed-exit tests).
    if not failed:
        for mo in f.get("match_output", []):
            if re.search(mo["pattern"], out):
                unless = mo.get("unless")
                if unless and re.search(unless, out):
                    continue
                return mo["message"]
    # stage 4: strip_lines_matching
    strips = [re.compile(p) for p in f.get("strip_lines_matching", [])]
    lines = out.split("\n")
    if strips:
        lines = [ln for ln in lines if not any(p.search(ln) for p in strips)]
    # stage 5: truncate_lines_at
    n = f.get("truncate_lines_at")
    if n:
        lines = [ln[:n] for ln in lines]
    # stage 7: max_lines
    m = f.get("max_lines")
    if m and len(lines) > m:
        lines = lines[:m]
    return "\n".join(lines)

def norm(s):
    return s.strip("\n")

fails = 0
total = 0
for path in sorted(pathlib.Path(sys.argv[1]).glob("*.toml")):
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    filters = data.get("filters", {})
    tests = data.get("tests", {})
    for fname, fdef in filters.items():
        for t in tests.get(fname, []):
            total += 1
            got = apply_filter(fdef, t["input"], t.get("failed", False))
            ok = norm(got) == norm(t["expected"])
            if not ok:
                fails += 1
                print(f"\nFAIL [{path.name}] {fname}: {t['name']}")
                print(f"  expected: {norm(t['expected'])!r}")
                print(f"  got     : {norm(got)!r}")
            else:
                print(f"ok   [{path.name}] {fname}: {t['name']}")
print(f"\n{total-fails}/{total} passed")
sys.exit(1 if fails else 0)
