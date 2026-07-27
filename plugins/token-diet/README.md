# token-diet

> 🌐 **English** · [Français](README.fr.md)

Token reduction for [Oh-My-Pi](https://github.com/can1357/oh-my-pi), reduced to
what OMP does **not** already do.

| Layer | What it does |
|---|---|
| **[lean-ctx](https://github.com/yvgude/lean-ctx)** (MIT) | A local Rust binary between the agent and its tools. `bash`, `read`, `grep`, `find` and `ls` are routed through it: command output **and** file reads, search results and project context are compressed, 75+ tools are recognised out of the box, and a persistent session cache makes an unchanged re-read cost a fraction of a fresh one. |
| **`caveman`** skill | Terse agent **output**. The one axis nothing else addresses — OMP and lean-ctx both work on what goes *into* the model. Preserves the user's language. |
| **`path-inject`** extension | Puts `~/.local/bin` on OMP's own PATH. OMP's shell snapshot runs `bash -c`, which sources no profile, so tooling installed there is invisible until a new login shell. |

## Install

```sh
bash plugins/token-diet/install.sh
```

Installs lean-ctx (brew, then the official installer, then npm), mirrors
upstream's `pi-lean-ctx` extension from npm into `~/.omp/agent/extensions/`, and
merges `config.snippet.yml`. lean-ctx is **non-fatal**: if the download fails the
install continues and tells you how to retry.

## What this plugin deliberately no longer ships

Each of these was removed because OMP or lean-ctx does it better:

| Removed | Superseded by |
|---|---|
| `ctx-wire` + a hand-written TOML filter per command | lean-ctx — compressing command output only meant maintaining a filter per command; four for `dotnet` alone |
| `read-dedup`, `context-dedup` | `compaction.supersedeReads` (default on), `dropUseless`, `pruneToolOutputs` |
| `cache-meter`, `/cache-health` | native statusline segments `cost`, `cache_read`, `cache_write`, `cache_hit` |
| `context-compress` | lean-ctx; ours was off by default and its sliding window mutated the already-sent prefix, busting the prompt cache |
| `tools.discoveryMode`, `tools.essentialOverride` | **removed in OMP 17.0.0** and deleted from config on load — `tools.xdev` replaced them and needs no configuration |
| the in-process "secret scrub" | `secrets.enabled` + `~/.omp/agent/secrets.yml`. The old one preserved high-entropy spans rather than removing them — it never redacted anything |
| `yagni`, `atlassian`, `context7`, `mcp-as-cli-skill-creator` skills | `yagni` deleted; Atlassian and Context7 are wired as their **official remote MCP servers** by the repo-root installer |

## Configuration

lean-ctx's knobs live in `~/.pi/agent/extensions/pi-lean-ctx/config.json` — that
extension resolves its config against `~/.pi`, not `~/.omp`, so the installer
writes it where the extension actually reads it. `mode: replace` swaps the native
tools outright; `additive` (default here) leaves both available.

## Measuring

`omp usage --history` and `omp stats` give real token and cost figures. The
`cache_hit` statusline segment shows whether the prompt cache is being hit. No
saving claimed here has been measured on your workload — measure before you trust
a number.
