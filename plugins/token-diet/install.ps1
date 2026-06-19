#requires -Version 5.1
<#
  token-diet installer (Windows) — installs the LATEST ctx-wire + CodeGraph and
  indexes EVERY git repo under a sources root. caveman/yagni ship as OMP skills.
  Flags: -DryRun, -Update (refresh existing), -Yes (non-interactive),
         -SourcesRoot <path> (parent of your repos; every git repo under it is
         indexed; default cwd, asked if interactive), -Depth N (default 3).
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Update, [switch]$Yes, [string]$SourcesRoot, [int]$Depth = 3, [switch]$NoConfig)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }

$BinDir = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# --- ctx-wire (transparent command-output compression + secret scrubbing) ----
if ((Have ctx-wire) -and $Update) {
  Say "Updating ctx-wire"; Run "ctx-wire update"
} elseif (Have ctx-wire) {
  Say "ctx-wire present — use -Update to refresh"
} else {
  Say "Installing latest ctx-wire"
  Run "irm https://ctx-wire.dev/install.ps1 | iex"
}
# Transparent PATH shims (no command prefix). 'init claude' only wires Claude Code;
# 'shims install' puts shims on PATH so OMP's bash tool routes through ctx-wire.
if ((Have ctx-wire) -or $DryRun) {
  Say "Installing ctx-wire PATH shims (transparent; no command prefix)"
  Run "ctx-wire shims install"
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

# --- Enable the bundled skills (caveman, yagni, codegraph, token-diet) -------
if (-not $NoConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  if ($DryRun) { Write-Host "  [dry-run] enable skills in $cfg" }
  else {
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'token-diet skills' -Quiet)) { Say "Skills already enabled in $cfg" }
    else { "`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg; Say "Enabled token-diet skills in $cfg" }
  }
}

# --- Load the context-transform extensions ----------------------------------
# OMP does not load extensions from a marketplace cache install; mirror them into
# the native user-extension dir (same pattern as dev-team/local-llm). Lossless
# read-dedup + context-dedup are on by default; context-compress runs at 'safe'
# (near-lossless) by default — lite|full (lossy) or off via TOKEN_DIET_CONTEXT_COMPRESS.
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\token-diet"
  if ($DryRun) { Write-Host "  [dry-run] mirror token-diet extensions -> $dest (OMP native ext dir)" }
  else {
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
    $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
    Say "read-dedup + context-dedup + context-compress (safe) loaded into $dest"
  }
}

Write-Host @"

==> token-diet is active:
    - ctx-wire transparently compresses command output (PATH shims). 'ctx-wire gain'
      shows savings; 'ctx-wire doctor' verifies. Re-run install after adding tools.
    - CodeGraph MCP is enabled (.mcp.json) and your repos are indexed —
      skill://codegraph for symbol/caller/architecture queries.
    - /caveman (terse output) and /yagni (write less code) are enabled.
    - Context extensions: re-reads of unchanged files + byte-identical repeated
      blocks are elided (LOSSLESS, on); old prose context is also compressed at
      'safe' by default (near-lossless). TOKEN_DIET_CONTEXT_COMPRESS=lite|full
      for more (lossy), or =off to disable.
    Restart omp so the MCP server + skills + extensions load.
"@ -ForegroundColor Green
