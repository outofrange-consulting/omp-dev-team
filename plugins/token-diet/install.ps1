#requires -Version 5.1
<#
  token-diet installer (Windows) — installs the LATEST RTK + CodeGraph and
  indexes EVERY git repo under a sources root. caveman ships as an OMP skill.
  Flags: -DryRun, -Update (refresh existing), -Yes (non-interactive),
         -SourcesRoot <path> (parent of your repos; every git repo under it is
         indexed; default cwd, asked if interactive), -Depth N (default 3).
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Update, [switch]$Yes, [string]$SourcesRoot, [int]$Depth = 3)
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
  # Prebuilt zip is the most reliable path on CI; cargo is the fallback.
  $zip = Join-Path $env:TEMP "rtk.zip"
  try {
    Run "Invoke-WebRequest -Uri 'https://github.com/rtk-ai/rtk/releases/latest/download/rtk-x86_64-pc-windows-msvc.zip' -OutFile '$zip'"
    Run "Expand-Archive -Path '$zip' -DestinationPath '$BinDir' -Force"
  } catch {
    if (Have cargo) { Run "cargo install --git https://github.com/rtk-ai/rtk" }
    else { Warn "could not install rtk (need network or cargo)" }
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

# --- Scan/index source repos with CodeGraph ---------------------------------
# Point CodeGraph at the ROOT of your sources; every git repo under it is indexed.
if (-not $SourcesRoot) {
  if (-not $Yes -and -not $DryRun -and -not [Console]::IsInputRedirected) {
    $ans = Read-Host "Sources ROOT to scan (every git repo under it is indexed)? [default: $(Get-Location)]"
    if (-not [string]::IsNullOrWhiteSpace($ans)) { $SourcesRoot = $ans }
  }
  if (-not $SourcesRoot) { $SourcesRoot = (Get-Location).Path }
}
function Index-One ($repo) {
  Say "  CodeGraph: $repo"
  Run "codegraph init `"$repo`""; Run "codegraph index `"$repo`""
}
if ((Have codegraph) -or $DryRun) {
  if (Test-Path (Join-Path $SourcesRoot '.git')) {
    Say "Scanning single repo: $SourcesRoot"; Index-One $SourcesRoot
  } else {
    Say "Scanning every git repo under: $SourcesRoot (depth $Depth)"
    $repos = @()
    if (-not $DryRun) {
      $repos = Get-ChildItem -Path $SourcesRoot -Recurse -Depth $Depth -Directory -Filter '.git' -ErrorAction SilentlyContinue | ForEach-Object { $_.Parent.FullName }
    }
    if ($repos.Count -gt 0) { foreach ($r in $repos) { Index-One $r }; Say "Indexed $($repos.Count) repo(s) under $SourcesRoot." }
    else { Warn "no git repos under $SourcesRoot — indexing it as a single project"; Index-One $SourcesRoot }
  }
}

Write-Host @"

==> token-diet tools ready. Final manual step: enable the CodeGraph MCP server.
    In your merged ~/.omp/agent .mcp.json set:  "codegraph": { ..., "enabled": true }
    - Shell output auto-routes through `rtk` (always-on rule) when present.
    - skill://codegraph for symbol/caller/architecture queries.
    - /caveman for terse output to save output tokens.
    Note: on native Windows RTK filters work but auto-rewrite needs WSL.
"@ -ForegroundColor Green
