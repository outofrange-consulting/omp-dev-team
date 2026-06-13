#requires -Version 5.1
<#
  copilot-preset installer (Windows) — config-only. Ensures OMP is present,
  guides Copilot login, and (optionally) appends config.snippet.yml.
  Flags: -DryRun, -ApplyConfig.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$ApplyConfig)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- OMP (the only requirement) ---------------------------------------------
if (Have omp) { Say "OMP present ($(omp --version 2>$null))" }
else { Say "Installing latest OMP"; Run "irm https://omp.sh/install.ps1 | iex" }

# --- Optionally apply the config snippet ------------------------------------
if ($ApplyConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  Say "Appending config.snippet.yml to $cfg"
  if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'copilot-preset' -Quiet)) {
      Write-Host "  (already present — skipping)"
    } else {
      "`n# --- copilot-preset ---`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg
      Write-Host "  appended. Review $cfg and adjust model ids to your plan."
    }
  }
}

Write-Host @"

==> copilot-preset ready. Final steps:
    1) Authenticate Copilot:  run omp, then /login -> GitHub Copilot
       (or set COPILOT_GITHUB_TOKEN / GH_TOKEN / GITHUB_TOKEN)
    2) Confirm models on your plan:  omp --list-models | Select-String github-copilot
    3) If you didn't pass -ApplyConfig, paste config.snippet.yml into
       ~/.omp/agent/config.yml. See pricing.md for the cheap-token mapping.
"@ -ForegroundColor Green
