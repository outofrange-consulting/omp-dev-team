// plugin-root.ts — export $DEV_TEAM_ROOT so ported skills can find their scripts.
//
// Upstream writes `${CLAUDE_PLUGIN_ROOT}/scripts/foo.py` in skill bodies. OMP
// substitutes that variable ONLY in discovery configs (MCP command/cwd/args/env),
// never inside a markdown body — it would reach the model as literal text and the
// command would fail. The port rewrites those to `$DEV_TEAM_ROOT/scripts/foo.py`;
// this extension is what makes that variable exist.
//
// It is set on process.env at load time, before any tool call, so every bash
// subprocess OMP spawns inherits it (OMP's shell snapshot runs `bash -c`, which
// sources no profile, so there is nowhere else to put it).

import { dirname, resolve } from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export default function pluginRoot(pi: ExtensionAPI): void {
	pi.setLabel("dev-team root");
	process.env.DEV_TEAM_ROOT = resolve(dirname(new URL(import.meta.url).pathname), "..");
}
