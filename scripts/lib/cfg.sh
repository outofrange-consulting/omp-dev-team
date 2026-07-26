#!/usr/bin/env bash
# cfg.sh — shared ~/.omp/agent/config.yml merge helpers.
#
# Sourced by the global installer AND by every per-plugin installer, so the two
# documented install paths ("run install.sh", then optionally "run the plugin's
# own install.sh") can never write conflicting or duplicated top-level YAML keys.
#
# THE BUG THIS EXISTS TO KILL: each per-plugin installer used to grep the config
# for its OWN banner string and, not finding it, append its WHOLE snippet. The
# global installer never writes those banners — so the README's own recommended
# sequence re-declared `modelRoles:`, `skills:`, `commands:`, `tools:`,
# `disabledProviders:`, `enabledModels:` and `retry:` as second top-level keys.
# Most YAML parsers silently last-wins on a duplicate top-level key, which is the
# exact opposite of the "your existing values are preserved" guarantee.
#
# Requires: $CFG set to the target config.yml path.

# cfg_has <topkey> — true only for a REAL top-level key: anchored at column 0, so
# an indented key, or the key appearing inside a string or comment, does not
# count. The key is regex-escaped before anchoring.
cfg_has() {
  local k; k="$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')"
  grep -qE "^${k}:([[:space:]]|\$)" "$CFG" 2>/dev/null
}

# cfg_add <topkey> ; YAML block on stdin ; append only if that key is absent.
cfg_add() {
  local key="$1" block; block="$(cat)"
  cfg_has "$key" && return 0
  printf '\n%s\n' "$block" >> "$CFG"
}

# cfg_add_snippet <snippet.yml> [label]
# Split a snippet into its top-level key blocks and append ONLY the blocks whose
# key is not already present in $CFG. Comments immediately preceding a key travel
# with that key, so a skipped block takes its documentation with it.
cfg_add_snippet() {
  local file="$1" label="${2:-config}" have add
  [ -f "$file" ] || { printf '  ! snippet not found: %s\n' "$file" >&2; return 0; }
  mkdir -p "$(dirname "$CFG")"; touch "$CFG"

  have="$(grep -oE '^[A-Za-z_][A-Za-z0-9_.-]*:' "$CFG" 2>/dev/null | tr -d ':' | sort -u)"
  add="$(awk -v have="$have" '
    BEGIN { n = split(have, a, "\n"); for (i = 1; i <= n; i++) if (a[i] != "") seen[a[i]] = 1 }
    function flush() { if (key != "" && !(key in seen)) printf "%s", buf }
    /^[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/ {
      flush(); key = $0; sub(/:.*$/, "", key)
      buf = pending $0 "\n"; pending = ""; next
    }
    key == "" { pending = pending $0 "\n"; next }
    { buf = buf $0 "\n" }
    END { flush() }
  ' "$file")"

  if [ -z "$add" ]; then
    printf '  ok %s config already present (nothing to add)\n' "$label"
    return 0
  fi
  printf '\n# --- %s (merged %s) ---\n%s\n' "$label" "$(date -u +%FT%TZ)" "$add" >> "$CFG"
  printf '  ok %s config merged: %s\n' "$label" \
    "$(printf '%s' "$add" | grep -cE '^[A-Za-z_][A-Za-z0-9_.-]*:([[:space:]]|$)') new top-level key(s)"
}
