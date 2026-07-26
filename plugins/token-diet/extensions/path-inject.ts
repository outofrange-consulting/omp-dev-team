// path-inject.ts — ensure ~/.local/bin is on PATH at OMP process startup.
//
// OMP spawns bash in non-interactive / non-login mode, so .bashrc and
// .profile are never sourced.  Tools this plugin installs to ~/.local/bin (the
// ctx-wire shims, ast-grep) are therefore invisible unless the user opened a
// fresh login shell after install.
//
// This extension mutates process.env.PATH once, at load time, before any tool
// call fires.  Every bash subprocess OMP spawns inherits the corrected PATH,
// so the tools are always found regardless of how the terminal was started.

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import * as os from "os";
import * as path from "path";

const LOCAL_BIN = path.join(os.homedir(), ".local", "bin");

function ensurePath(dir: string): boolean {
	const current = process.env.PATH ?? "";
	const parts = current.split(":");
	if (parts.includes(dir)) return false;
	process.env.PATH = `${dir}:${current}`;
	return true;
}

export default function pathInject(_pi: ExtensionAPI) {
	const added = ensurePath(LOCAL_BIN);
	if (added) {
		// Silently injected — no noise in the UI.  Visible via `echo $PATH`
		// in any bash tool call or by checking process.env.PATH in debug mode.
	}
}
