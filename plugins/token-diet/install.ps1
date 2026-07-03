#requires -Version 5.1
<#
  token-diet installer (Windows) — installs the LATEST ctx-wire. caveman/yagni ship
  as OMP skills. Also sets up acli (Atlassian CLI), ast-grep, and the ctx7 docs
  CLI. Everything is refreshed to latest by default.
  (Symbolic C# navigation/edit AND precise C# semantics — rename, exact
  references, diagnostics, hover — are provided by the dev-team plugin's
  Serena-backed serena-forge integration, not token-diet.)
  Flags: -NoUpdate (keep tools already installed), -Yes (non-interactive), -NoConfig,
         -NoCleanup (don't remove obsolete predecessors: codebase-memory-mcp, CodeGraph, RTK, csharp-ls).
  Env (acli): ACLI_SITE / ACLI_EMAIL / ACLI_TOKEN — non-interactive acli auth,
         auto-run on install when acli isn't already authenticated.
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
# semantics. Those are gone now (symbolic C# code intel AND precise C#
# semantics moved to the dev-team plugin's Serena-backed serena-forge
# integration; ctx-wire replaced RTK), but an upgrade/uninstall does NOT remove
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
  # precise C# semantics now live in the dev-team plugin's serena-forge
  # integration (Serena's Roslyn backend), not token-diet.
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

# --- acli (official Atlassian CLI — our go-to for Atlassian) -----------------
if ((Have acli) -and $NoUpdate) { Say "acli present" }
else {
  Say "Installing Atlassian CLI (acli)"
  try { Invoke-WebRequest -Uri 'https://acli.atlassian.com/windows/latest/acli_windows_amd64/acli.exe' -OutFile (Join-Path $BinDir 'acli.exe') }
  catch { Warn "acli download failed — see https://developer.atlassian.com/cloud/acli/" }
}

# Authenticate (Jira) when not already logged in — runs automatically (no
# Y/n gate); non-interactive installs can supply $env:ACLI_SITE/ACLI_EMAIL/ACLI_TOKEN.
if (Have acli) {
  acli jira auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    if ($env:ACLI_SITE -and $env:ACLI_EMAIL -and $env:ACLI_TOKEN) {
      $env:ACLI_TOKEN | acli jira auth login --site $env:ACLI_SITE --email $env:ACLI_EMAIL --token *> $null
      if ($LASTEXITCODE -eq 0) { Write-Host "  acli authenticated ($($env:ACLI_SITE))" } else { Warn "acli auth failed — run 'acli jira auth login' manually." }
    } elseif (-not $Yes) {
      Say "Authenticating acli (Jira/Confluence)"
      $acliSite  = Read-Host "    Atlassian site (e.g. mysite.atlassian.net)"
      $acliEmail = Read-Host "    Email"
      $acliToken = Read-Host "    API token (id.atlassian.com -> Security -> API tokens)" -AsSecureString
      $acliPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($acliToken))
      if ($acliSite -and $acliEmail -and $acliPlain) {
        $acliPlain | acli jira auth login --site $acliSite --email $acliEmail --token *> $null
        if ($LASTEXITCODE -eq 0) { Write-Host "  acli authenticated ($acliSite)" } else { Warn "acli auth failed — run 'acli jira auth login' manually." }
      } else { Warn "incomplete input — run 'acli jira auth login' manually." }
    } else {
      Warn "acli not authenticated — set ACLI_SITE/ACLI_EMAIL/ACLI_TOKEN env vars, or run 'acli jira auth login' manually."
    }
  }
}

# --- ast-grep (structural search/rewrite) -----------------------------------
if ((Have ast-grep) -and $NoUpdate) { Say "ast-grep present" }
elseif (Have winget) { Say "Installing ast-grep (winget)"; Run "winget install --id ast-grep.ast-grep -e --accept-source-agreements --accept-package-agreements" }
elseif (Have npm) { Say "Installing ast-grep (npm)"; Run "npm install -g @ast-grep/cli" }
else { Warn "need npm or winget to install ast-grep — see https://ast-grep.github.io" }

# --- ctx7 CLI (context7 library documentation) ------------------------------
if (Have npm) {
  if ((Have ctx7) -and $NoUpdate) { Say "ctx7 CLI present" }
  else { Say "Installing ctx7 CLI"; Run "npm install -g ctx7" }
} else { Warn "npm not found — ctx7 unavailable (install Node.js)" }

# --- Enable the bundled skills (caveman, yagni, token-diet) -
if (-not $NoConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'token-diet skills' -Quiet)) { Say "Skills already enabled in $cfg" }
  else { "`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg; Say "Enabled token-diet skills in $cfg" }
}

# --- Load the context-transform extensions ----------------------------------
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\token-diet"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "read-dedup + context-dedup + context-compress (safe) loaded into $dest"
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
Warn "ctx-wire shims, acli, ast-grep, and ctx7 write to $BinDir / user PATH, and this script updates PATH for NEW processes only. An already-running OMP process keeps its old PATH (these tools invisible) until you RESTART OMP."

Say "token-diet active: ctx-wire shims, ast-grep, ctx7, acli, /caveman + /yagni. Restart omp."
