#requires -Version 5.1
<#
  token-diet installer (Windows) — installs the LATEST RTK + CodeGraph and
  indexes the current project. caveman ships as an OMP skill (no install).
  Flags: -DryRun (print only), -Update (refresh existing).
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Update)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }

$BinDir = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# --- RTK (Rust Token Killer): prebuilt zip -> ~/.local/bin ------------------
if ((Have rtk) -and -not $Update) {
  Say "RTK present ($(rtk --version 2>$null)) — use -Update to refresh"
} else {
  Say "Installing latest RTK (Rust Token Killer)"
  if (Have winget) { Run "winget install --id rtk-ai.rtk -e --accept-source-agreements --accept-package-agreements" }
  elseif (Have cargo) { Run "cargo install --git https://github.com/rtk-ai/rtk" }
  else {
    $zip = Join-Path $env:TEMP "rtk.zip"
    Run "Invoke-WebRequest -Uri 'https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-pc-windows-msvc.zip' -OutFile '$zip'"
    Run "Expand-Archive -Path '$zip' -DestinationPath '$BinDir' -Force"
  }
}

# --- CodeGraph (MCP) --------------------------------------------------------
if ((Have codegraph) -and -not $Update) {
  Say "CodeGraph present — use -Update to refresh"
} else {
  Say "Installing latest CodeGraph"
  Run "irm https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.ps1 | iex"
}

# Ensure ~/.local/bin is on PATH (user scope)
if (";$env:Path;" -notlike "*;$BinDir;*") {
  Say "Adding $BinDir to your user PATH"
  if (-not $DryRun) {
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
    $env:Path = "$env:Path;$BinDir"
  } else { Write-Host "  [dry-run] setx PATH += $BinDir" }
}

# --- Index the current project ----------------------------------------------
if ((Have codegraph) -or $DryRun) {
  Say "Indexing this project with CodeGraph (cwd: $(Get-Location))"
  Run "codegraph init ."   ; Run "codegraph index ."  ; Run "codegraph status ."
}

Write-Host @"

==> token-diet tools ready. Final manual step: enable the CodeGraph MCP server.
    In your merged ~/.omp/agent .mcp.json set:  "codegraph": { ..., "enabled": true }
    - Shell output auto-routes through `rtk` (always-on rule) when present.
    - skill://codegraph for symbol/caller/architecture queries.
    - /caveman for terse output to save output tokens.
    Note: on native Windows RTK filters work but auto-rewrite needs WSL.
"@ -ForegroundColor Green
