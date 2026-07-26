#requires -Version 5.1
<#
  dev-team installer (Windows) — prerequisite checker + optional config apply.
  The agentic dev team is all-cloud: no local model backend to install. It needs
  OMP + git; a few skills optionally use gh / semgrep / docker / python. The
  bundled serena-forge integration additionally needs .NET 10+ (installed below
  if missing) and uvx (checked only, never auto-installed) for its C# backend.
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

# --- Required: git + optional tools -----------------------------------------
Say "Checking prerequisites"
if (Have git) { Ok "git" } else { Warn "git missing — required for branch-workflow / /pr" }
foreach ($t in 'gh','semgrep','docker','python') {
  if (Have $t) { Ok "$t (optional)" } else { Warn "$t not found (optional — used by some skills)" }
}

# --- .NET SDK (bundled serena-forge integration's C# backend needs .NET 10+) -
# serena-forge (Serena's Roslyn-based Microsoft.CodeAnalysis.LanguageServer)
# requires .NET 10+ on the host; Serena itself launches via uvx (checked below,
# never auto-installed here) and downloads the Roslyn LS from NuGet on first
# C# use. Skip harmlessly if you never touch .cs files.
function Dotnet-Major {
  if (Have dotnet) { ((dotnet --version 2>$null) -split '\.')[0] } else { '0' }
}
if ([int](Dotnet-Major) -lt 10) {
  Say "Installing .NET SDK (serena-forge's C# backend needs .NET 10+)"
  try {
    $dis = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $dis
    & $dis -Channel LTS -InstallDir (Join-Path $HOME '.dotnet')
    $env:DOTNET_ROOT = Join-Path $HOME '.dotnet'
    $env:Path = "$($env:DOTNET_ROOT);$($env:DOTNET_ROOT)\tools;$env:Path"
    [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $env:DOTNET_ROOT, 'User')
  } catch { Warn ".NET SDK install failed: $_" }
}
if ([int](Dotnet-Major) -ge 10) { Ok "dotnet $(dotnet --version) (serena-forge C# backend)" }
elseif (Have dotnet) { Warn "dotnet $(dotnet --version) found but serena-forge's C# backend needs .NET 10+ (see https://dot.net)" }
else { Warn "dotnet not found — serena-forge's C# backend needs .NET 10+ (see https://dot.net; harmless to skip if you never work in C#)" }

# --- uvx (from uv) — launches the bundled Serena MCP server -----------------
# Never auto-installed here (a package manager should own it, and Serena's
# setup skills explicitly tell users to install uv themselves, not the agent).
if (Have uvx) { Ok "uvx ($(uvx --version 2>$null))" }
else { Warn "uvx not found — serena-forge's Serena MCP server can't launch (install uv: https://github.com/astral-sh/uv)" }

# --- Optionally apply the config snippet ------------------------------------
if ($ApplyConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  Say "Appending config.snippet.yml to $cfg"
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'dev-team —' -Quiet)) {
    Write-Host "  (already present — skipping)"
  } else {
    "`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg
    Write-Host "  appended."
  }
}

# --- Load the guard extensions ----------------------------------------------
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\dev-team"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "guards loaded into $dest"
}

Say "dev-team ready. Restart omp, then drive the workflow: /specs -> /plan -> /build -> /pr."
