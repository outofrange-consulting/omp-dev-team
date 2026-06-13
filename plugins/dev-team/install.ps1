#requires -Version 5.1
<#
  dev-team installer (Windows) — prerequisite checker + optional config apply.
  The agentic dev team is all-cloud: no local model backend to install. It needs
  OMP + git; a few skills optionally use gh / semgrep / docker / python.
  Flags: -DryRun, -ApplyConfig.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$ApplyConfig)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }

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

# --- Optionally apply the config snippet ------------------------------------
if ($ApplyConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  Say "Appending config.snippet.yml to $cfg"
  if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'dev-team —' -Quiet)) {
      Write-Host "  (already present — skipping)"
    } else {
      "`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg
      Write-Host "  appended."
    }
  }
}

Write-Host @"

==> dev-team ready. Next:
    1) If you didn't pass -ApplyConfig, paste config.snippet.yml into ~/.omp/agent/config.yml.
    2) Run omp, then drive the workflow: /specs -> /plan -> /build -> /pr.
    Keep the small tier cheap: modelRoles.smol (default claude-haiku-4-5; or a
    github-copilot model via the copilot-preset plugin).
"@ -ForegroundColor Green
