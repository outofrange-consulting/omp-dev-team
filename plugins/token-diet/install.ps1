#requires -Version 5.1
<#
  token-diet installer (Windows) — v2.0.0, refocused.
  Installs the LATEST ctx-wire + the EN/FR filter pack for the four `dotnet`
  commands OMP's native shellMinimizer does NOT cover (publish, pack, run,
  tool), mirrors the extensions and the always-on rule into ~/.omp/agent, and
  merges config.snippet.yml. caveman ships as an OMP skill.
  NOT installed any more (OMP does it, or it moved):
    acli / the atlassian skill -> official remote MCP server, wired by the
                                  repo-root install.sh
    ctx7 / the context7 skill  -> official remote MCP server, ditto
  Flags: -NoUpdate (keep tools already installed), -NoConfig,
         -NoCleanup (don't remove obsolete predecessors: codebase-memory-mcp,
         CodeGraph, RTK, csharp-ls).
         -Yes is accepted for parity with the other installers; nothing prompts.
#>
[CmdletBinding()]
param([switch]$NoUpdate, [switch]$Yes, [switch]$NoConfig, [switch]$NoCleanup)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }

$BinDir = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# --- Clean up obsolete predecessors on (re)install --------------------------
# Earlier token-diet versions installed a code-graph MCP server (first CodeGraph,
# then codebase-memory-mcp), before ctx-wire, RTK, and a csharp-ls LSP for C#
# semantics. Those are gone now (C# navigation and semantics go through OMP's
# native `lsp` tool, which ships `omnisharp` as a built-in default for
# `.cs`/`.csx`; ctx-wire replaced RTK), but an upgrade/uninstall does NOT remove
# what a past install left on the machine. Unregister the dead MCP servers
# from OMP's mcp.json, uninstall the obsolete csharp-ls dotnet tool + its
# lsp.json entry, and remove the leftover binaries/dirs. Idempotent,
# existence-guarded, only touches these exact obsolete names. Skip with -NoCleanup.
function Cleanup-Obsolete {
  if ($NoCleanup) { return }
  Say "Cleaning up obsolete tools (codebase-memory-mcp, CodeGraph, RTK, csharp-ls)"
  $removed = $false

  # 1) Unregister the obsolete MCP servers from OMP's mcp.json.
  $mcp = Join-Path $HOME ".omp\agent\mcp.json"
  if (Test-Path $mcp) {
    try {
      $cfg = Get-Content -Raw -Path $mcp | ConvertFrom-Json
      if ($cfg.mcpServers) {
        $gone = @()
        foreach ($k in @('codebase-memory','codebase-memory-mcp','codegraph','code-graph')) {
          if ($cfg.mcpServers.PSObject.Properties.Name -contains $k) {
            $cfg.mcpServers.PSObject.Properties.Remove($k); $gone += $k
          }
        }
        if ($gone.Count -gt 0) {
          ($cfg | ConvertTo-Json -Depth 20) | Set-Content -Path $mcp -Encoding UTF8
          Say ("  unregistered MCP server(s): " + ($gone -join ', ')); $removed = $true
        }
      }
    } catch { Warn "  could not edit $mcp ($_) — remove any codebase-memory-mcp/codegraph entry by hand" }
  }

  # 2) Remove leftover binaries (exact names only, existence-guarded).
  $binNames = @('codebase-memory-mcp','codegraph','rtk')
  $binDirs  = @($BinDir, (Join-Path $HOME '.cargo\bin'), (Join-Path $HOME '.bun\bin'))
  foreach ($d in $binDirs) {
    foreach ($n in $binNames) {
      foreach ($ext in @('', '.exe', '.cmd')) {
        $p = Join-Path $d ($n + $ext)
        if (Test-Path $p) { Remove-Item -Force -ErrorAction SilentlyContinue $p; Say "  removed $p"; $removed = $true }
      }
    }
  }

  # 3) Remove obsolete install/data dirs (exact tool-named dirs only).
  $dirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp'),
    (Join-Path $env:LOCALAPPDATA 'codegraph'),
    (Join-Path $env:LOCALAPPDATA 'codebase-memory-mcp'),
    (Join-Path $HOME '.codegraph'),
    (Join-Path $HOME '.codebase-memory-mcp')
  )
  foreach ($d in $dirs) {
    if ($d -and (Test-Path $d)) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $d; Say "  removed $d"; $removed = $true }
  }

  # 4) Uninstall the obsolete csharp-ls dotnet tool + its lsp.json entry —
  # C# semantics now come from OMP's native `lsp` tool + omnisharp, so a stale
  # csharp-ls entry in lsp.json only competes with it.
  if ((Have dotnet) -and ((dotnet tool list -g 2>$null) -match '^csharp-ls\s')) {
    Run "dotnet tool uninstall -g csharp-ls"
    Say "  uninstalled csharp-ls (dotnet tool)"; $removed = $true
  }
  $lspPath = Join-Path $HOME ".omp\agent\lsp.json"
  if (Test-Path $lspPath) {
    try {
      $lspCfg = Get-Content -Raw -Path $lspPath | ConvertFrom-Json
      if ($lspCfg.servers -and ($lspCfg.servers.PSObject.Properties.Name -contains 'csharp-ls')) {
        $lspCfg.servers.PSObject.Properties.Remove('csharp-ls')
        if ($lspCfg.servers.PSObject.Properties.Count -gt 0) {
          ($lspCfg | ConvertTo-Json -Depth 20) | Set-Content -Path $lspPath -Encoding UTF8
        } else {
          Remove-Item -Force $lspPath
        }
        Say "  removed csharp-ls from lsp.json"; $removed = $true
      }
    } catch { Warn "  could not edit $lspPath ($_) — remove any csharp-ls entry by hand" }
  }

  if (-not $removed) { Say "  nothing obsolete found (already clean)" }
}
Cleanup-Obsolete

# --- ctx-wire (transparent command-output compression + secret scrubbing) ----
if ((Have ctx-wire) -and $NoUpdate) {
  Say "ctx-wire present"
} elseif (Have ctx-wire) {
  Say "Updating ctx-wire"; Run "ctx-wire update"
} else {
  Say "Installing latest ctx-wire"; Run "irm https://ctx-wire.dev/install.ps1 | iex"
}
if (Have ctx-wire) { Say "Installing ctx-wire PATH shims"; Run "ctx-wire shims install" }

# Ensure ~/.local/bin is on PATH (user scope)
if (";$env:Path;" -notlike "*;$BinDir;*") {
  Say "Adding $BinDir to your user PATH"
  $userPath = [Environment]::GetEnvironmentVariable('Path','User')
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
  $env:Path = "$env:Path;$BinDir"
}

# --- ast-grep (structural search/rewrite) -----------------------------------
if ((Have ast-grep) -and $NoUpdate) { Say "ast-grep present" }
elseif (Have winget) { Say "Installing ast-grep (winget)"; Run "winget install --id ast-grep.ast-grep -e --accept-source-agreements --accept-package-agreements" }
elseif (Have npm) { Say "Installing ast-grep (npm)"; Run "npm install -g @ast-grep/cli" }
else { Warn "need npm or winget to install ast-grep — see https://ast-grep.github.io" }

# NOTE (parity gap, deliberate): the EN+FR ctx-wire filter merge lives in
# install.sh only. ctx-wire's Windows user-tier filter path is not pinned here,
# so rather than guess at it we leave `ctx-wire` to its own defaults on Windows.
# Run `ctx-wire verify` after adding filters/*.toml by hand if you need them.

# --- Merge config.snippet.yml into ~/.omp/agent/config.yml -------------------
# Same contract as scripts/lib/cfg.sh on the Unix side: append ONLY the
# top-level keys that are not already declared. The old behaviour (grep for one
# banner, else append the WHOLE snippet) re-declared `skills:`, `commands:` and
# `disabledProviders:` as second top-level keys whenever the repo-root installer
# had already written them — and most YAML parsers silently last-wins on a
# duplicate top-level key, which is the opposite of "your values are preserved".
if (-not $NoConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if (-not (Test-Path $cfg)) { New-Item -ItemType File -Force -Path $cfg | Out-Null }

  $existing = @(Select-String -Path $cfg -Pattern '^([A-Za-z_][A-Za-z0-9_.-]*):(\s|$)' -AllMatches |
                ForEach-Object { $_.Matches[0].Groups[1].Value })
  $blocks = [ordered]@{}   # top-level key -> its lines (preceding comments included)
  $key = ''; $pending = @(); $buf = @()
  foreach ($line in (Get-Content (Join-Path $Here 'config.snippet.yml'))) {
    if ($line -match '^([A-Za-z_][A-Za-z0-9_.-]*):(\s|$)') {
      if ($key -ne '') { $blocks[$key] = $buf }
      $key = $Matches[1]; $buf = $pending + $line; $pending = @()
    } elseif ($key -eq '') { $pending += $line }
    else { $buf += $line }
  }
  if ($key -ne '') { $blocks[$key] = $buf }

  $add = @()
  foreach ($k in $blocks.Keys) { if ($existing -notcontains $k) { $add += $blocks[$k] } }
  if ($add.Count -eq 0) { Say "token-diet config already present in $cfg (nothing to add)" }
  else {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    ("`n# --- token-diet (merged $stamp) ---`n" + ($add -join "`n") + "`n") | Add-Content -Path $cfg
    Say "token-diet config merged into $cfg"
  }
}

# --- Load the context-transform extensions ----------------------------------
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\token-diet"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "extensions loaded into ${dest}: path-inject (always on) + context-compress (OFF unless TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full)"
}

# --- Load the always-on OMP-native rule (ctx-wire token-tool routing) ---
# NOTE: OMP's omp-plugins rule provider only discovers rules/*.md inside
# *configured* extension package roots (extensions:/-e/npm-linked) — a bare
# marketplace install of this plugin is NOT one, so rules/token-tools.md would
# silently never load (same gap the extensions/ mirror above works around).
# Copy it into ~/.omp/agent/rules, which the native provider (priority 100)
# always scans, namespaced so it never collides with another plugin's rule.
$rulesSrc = Join-Path $Here 'rules'
if (Test-Path $rulesSrc) {
  $rulesDest = Join-Path $HOME ".omp\agent\rules"
  New-Item -ItemType Directory -Force -Path $rulesDest | Out-Null
  Get-ChildItem -Path $rulesSrc -Filter '*.md' | ForEach-Object {
    Copy-Item -Force $_.FullName (Join-Path $rulesDest "token-diet-$($_.Name)")
  }
  Say "token-tools rule installed to $rulesDest (native, always-on)"
}

# --- Heads-up: OMP context-file precedence -----------------------------------
# OMP reads ONE context file at user scope: native ~/.omp/agent/AGENTS.md
# (priority 100) if present, else ~/.claude/CLAUDE.md (priority 80, verbatim).
# A CLAUDE.md may carry Claude-Code-only advice (e.g. its own ctx-wire block
# telling the agent to prefer raw shell over built-in tools — correct for
# Claude Code, wrong for OMP, which already routes through read/grep/glob and
# this plugin's own token-tools rule). OMP inherits that by accident, not
# design, whenever no native AGENTS.md exists yet.
$claudeMd = Join-Path $HOME ".claude\CLAUDE.md"
$agentsMd = Join-Path $HOME ".omp\agent\AGENTS.md"
if (-not $NoConfig -and (Test-Path $claudeMd) -and -not (Test-Path $agentsMd)) {
  Warn "no ~/.omp/agent/AGENTS.md - OMP falls back to reading ~/.claude/CLAUDE.md verbatim, including any Claude-Code-only guidance (e.g. 'prefer shell over built-in tools'). Consider a native AGENTS.md with just the conventions that apply to OMP."
}

# NOTE: unlike install.sh, we can't reliably probe an already-running OMP
# process's inherited environment from here (no non-interactive-login-shell
# equivalent) — so this warning is unconditional rather than detected.
Warn "ctx-wire shims and ast-grep write to $BinDir / user PATH, and this script updates PATH for NEW processes only. An already-running OMP process keeps its old PATH (these tools invisible) until you RESTART OMP."

Say "token-diet active: ctx-wire shims, ast-grep, provider isolation, /caveman. Restart omp."

# Cost + prompt-cache visibility is native — v1.x forked OMP's own status-line
# renderer to inline it; OMP ships the numbers as first-class segments
# (omp packages/coding-agent/src/modes/components/status-line/segments.ts:
# cost, context_pct, cache_read, cache_write, cache_hit, usage).
Say "For live cost/cache numbers, add to ~/.omp/agent/config.yml:"
@'
    statusLine:
      preset: custom
      rightSegments: [cost, cache_hit, cache_write, context_pct, usage]
'@ | Write-Host
