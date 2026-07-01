// path-inject.ts — ensure ~/.local/bin is on PATH at OMP process startup.
//
// OMP spawns bash in non-interactive / non-login mode, so .bashrc and
// .profile are never sourced. install.sh lands the `pup` CLI in
// ~/.local/bin (Homebrew installs elsewhere, but the prebuilt-tarball
// fallback used everywhere else does not), so it's invisible to every bash
// tool call unless the user happened to open a fresh login shell after
// install — restarting OMP alone does not fix it, since the OMP process's
// own env is what's stale.
//
// This extension mutates process.env.PATH once, at load time, before any
// tool call fires. Every bash subprocess OMP spawns inherits the corrected
// PATH, so `pup` is always found regardless of how the terminal was started.
//
// Kept as its own copy rather than importing token-diet's — plugins in this
// marketplace are independent and share nothing (see README), so datadog
// must not depend on token-diet being installed.

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
	ensurePath(LOCAL_BIN);
}
