#requires -Version 5.1
<#
  copilot-preset installer (Windows) — config-only. Ensures OMP is present,
  guides Copilot login, and (optionally) appends config.snippet.yml.
  Flags: -ApplyConfig, -NoUpdate (no-op), -Yes (no-op).
#>
[CmdletBinding()]
param([switch]$ApplyConfig, [switch]$NoUpdate, [switch]$Yes)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- OMP (the only requirement) ---------------------------------------------
if (Have omp) { Say "OMP present ($(omp --version 2>$null))" }
else { Say "Installing latest OMP"; Run "irm https://omp.sh/install.ps1 | iex" }

# --- Optionally apply the config snippet ------------------------------------
if ($ApplyConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  Say "Appending config.snippet.yml to $cfg"
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'copilot-preset' -Quiet)) {
    Write-Host "  (already present — skipping)"
  } else {
    "`n# --- copilot-preset ---`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg
    Write-Host "  appended. Review $cfg and adjust model ids to your plan."
  }
}

Say "copilot-preset ready. Authenticate: run omp -> /login -> GitHub Copilot (or set COPILOT_GITHUB_TOKEN - that exact name only; there is no GH_TOKEN/GITHUB_TOKEN fallback). See pricing.md."
