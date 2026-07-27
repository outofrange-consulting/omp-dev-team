#requires -Version 5.1
<#
  dev-team installer (Windows).

  This plugin is a VERBATIM port of upstream agentic-dev-team v10.20.0, whose
  entire hook and script layer is Python, run unmodified through
  extensions/hook-bridge.ts. Python 3 is therefore a HARD requirement, not an
  optional extra: without it every guard, gate and telemetry hook is inert.

  A POSIX `sh` is also wanted, because upstream's own interpreter resolver
  (hooks/py.sh) is a shell script by necessity — it runs before any Python is
  guaranteed. Git for Windows ships one; without it the bridge calls Python
  directly instead.

  Flags: -ApplyConfig, -NoUpdate (no-op), -Yes (no-op).
#>
[CmdletBinding()]
param([switch]$ApplyConfig, [switch]$NoUpdate, [switch]$Yes)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Required: OMP ----------------------------------------------------------
if (Have omp) { Ok "omp ($(omp --version 2>$null))" }
else { Say "Installing latest OMP"; Run "irm https://omp.sh/install.ps1 | iex" }

# --- Required: Python 3 -----------------------------------------------------
# Probed the way upstream's py.sh does — by EXECUTING each candidate rather than
# just locating it — so the WindowsApps `python3` app-execution-alias stub, which
# resolves on PATH but refuses to run non-interactively, is rejected on behaviour.
Say "Checking prerequisites"
$MissingPy = $true
foreach ($cand in @($env:DEV_TEAM_PYTHON, 'python3', 'py -3', 'python')) {
  if (-not $cand) { continue }
  $parts = $cand -split ' '
  if (-not (Have $parts[0])) { continue }
  try {
    $rest = @()
    if ($parts.Length -gt 1) { $rest = $parts[1..($parts.Length - 1)] }
    $v = & $parts[0] @rest -c 'import sys; print(sys.version.split()[0])' 2>$null
    if ($LASTEXITCODE -eq 0 -and "$v" -match '^3\.') {
      Ok "python $v (via '$cand')"; $MissingPy = $false; break
    }
  } catch { }
}
if ($MissingPy) {
  Warn "NO PYTHON 3 FOUND. dev-team's hook layer (guards, gates, telemetry) will be INERT."
  Warn "Install Python 3.8+, or set DEV_TEAM_PYTHON to a working interpreter."
}

if (Have git) { Ok "git" } else { Warn "git missing — required for branch-workflow / /skill:pr" }
if (Have sh) { Ok "sh (POSIX shell, runs hooks/py.sh)" }
else { Warn "no POSIX 'sh' on PATH — install Git for Windows so hooks/py.sh can run" }
foreach ($t in 'gh','semgrep','docker') {
  if (Have $t) { Ok "$t (optional)" } else { Warn "$t not found (optional — used by some skills)" }
}

# --- Optionally merge the config snippet ------------------------------------
# Per TOP-LEVEL KEY, never the whole file. Appending the whole snippet is what
# produced duplicate top-level YAML keys once the global installer had already
# written them — parsers resolve those last-wins, the opposite of the "your
# existing values are preserved" guarantee. Mirrors scripts/lib/cfg.sh.
if ($ApplyConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  Say "Merging config.snippet.yml into $cfg"
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if (-not (Test-Path $cfg)) { New-Item -ItemType File -Force -Path $cfg | Out-Null }

  $existing = @{}
  foreach ($line in (Get-Content $cfg)) {
    if ($line -match '^([A-Za-z_][A-Za-z0-9_.-]*):(\s|$)') { $existing[$Matches[1]] = $true }
  }

  $add     = New-Object System.Collections.Generic.List[string]
  $pending = New-Object System.Collections.Generic.List[string]
  $buf     = New-Object System.Collections.Generic.List[string]
  $key     = $null
  $added   = 0

  foreach ($line in (Get-Content (Join-Path $Here 'config.snippet.yml'))) {
    if ($line -match '^([A-Za-z_][A-Za-z0-9_.-]*):(\s|$)') {
      if ($key -and -not $existing.ContainsKey($key)) { $added++; foreach ($l in $buf) { $add.Add($l) } }
      $key = $Matches[1]
      $buf = New-Object System.Collections.Generic.List[string]
      foreach ($p in $pending) { $buf.Add($p) }
      $pending = New-Object System.Collections.Generic.List[string]
      $buf.Add($line)
    } elseif (-not $key) { $pending.Add($line) } else { $buf.Add($line) }
  }
  if ($key -and -not $existing.ContainsKey($key)) { $added++; foreach ($l in $buf) { $add.Add($l) } }

  if ($add.Count) {
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    ("`n# --- dev-team (merged $stamp) ---`n" + ($add -join "`n")) | Add-Content -Path $cfg
    Ok "dev-team config merged: $added new top-level key(s)"
  } else {
    Ok "dev-team config already present (nothing to add)"
  }
}

# --- Load the extensions + the runtime they drive ----------------------------
# OMP does NOT load extension modules from a marketplace cache install, so they
# are mirrored into OMP's native user extension dir.
#
# hooks/ AND scripts/ MUST travel with them: hook-bridge.ts resolves its plugin
# root from its own location, so after mirroring that root IS this dest dir.
# Mirroring extensions/ alone would leave the bridge looking for hooks/py.sh in a
# directory that does not contain it, and the whole guard layer would be silently
# inert. $DEV_TEAM_ROOT (exported by plugin-root.ts) resolves the same way, which
# is what ported skill bodies use to find scripts/.
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\dev-team"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  Copy-Item -Recurse -Force (Join-Path $Here 'hooks')   (Join-Path $dest 'hooks')
  Copy-Item -Recurse -Force (Join-Path $Here 'scripts') (Join-Path $dest 'scripts')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "extensions + hooks + scripts loaded into ${dest}"
}

if ($MissingPy) {
  Warn "dev-team installed, but WITHOUT Python 3 its hook layer does nothing."
  Warn "Install Python 3.8+ (or set DEV_TEAM_PYTHON) and restart omp."
}
Say "dev-team ready. Restart omp, then drive the workflow: /skill:specs -> /skill:plan -> /skill:build -> /skill:pr (or /skill:ship for all of it)."
