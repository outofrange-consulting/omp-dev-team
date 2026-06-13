#requires -Version 5.1
<#
  omp-dev-team — global installer (Windows).
  Installs OMP, registers this marketplace, then interactively offers each plugin
  and its config. Updates the user PATH so everything works in new shells.
  Flags:
    -Yes       non-interactive: install all plugins + apply default configs
    -DryRun    print actions without executing
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$DryRun)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Market = 'omp-dev-team'

function Bold ($m) { Write-Host "`n$m" -ForegroundColor White }
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }
function Ask ($q, $def = 'Y') {
  if ($Yes) { return $true }
  $hint = if ($def -eq 'Y') { '[Y/n]' } else { '[y/N]' }
  $ans = Read-Host "$q $hint"
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $def }
  return ($ans -match '^(y|Y)')
}
function Ensure-Path ($dir) {
  if (-not (Test-Path $dir)) { return }
  if (";$env:Path;" -like "*;$dir;*") { return }
  $env:Path = "$dir;$env:Path"
  if ($DryRun) { Write-Host "  [dry-run] persist user PATH += $dir"; return }
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  if (";$u;" -notlike "*;$dir;*") { [Environment]::SetEnvironmentVariable('Path', "$u;$dir", 'User') }
}

Bold "omp-dev-team installer"
Write-Host "Repo: $Root"

# --- 1) OMP ----------------------------------------------------------------
if (Have omp) { Ok "omp present ($(omp --version 2>$null))" }
else { Say "Installing OMP (latest)"; Run "irm https://omp.sh/install.ps1 | iex" }
Ensure-Path (Join-Path $HOME ".local\bin")
if (-not (Have omp)) { Warn "omp not on PATH yet — open a new shell after this" }

# --- 2) Register the marketplace -------------------------------------------
if (Have omp) { Say "Registering marketplace ($Market) from local checkout"; Run "omp plugin marketplace add `"$Root`"" }

function Plug ($name, $dir) {
  if (Have omp) { Run "omp plugin install $name@$Market" }
  $ps1 = Join-Path $dir 'install.ps1'
  if (Test-Path $ps1) {
    $args = @(); if ($DryRun) { $args += '-DryRun' }
    Run "& `"$ps1`" $($args -join ' ')"
  }
}

# --- 3) Per-plugin prompts --------------------------------------------------
Bold "Plugins"

if (Ask "Install dev-team (agentic dev team: /specs -> /plan -> /build -> /pr)?") {
  Plug 'dev-team' (Join-Path $Root 'plugins\dev-team')
  if (Ask "  Apply dev-team config to ~/.omp/agent/config.yml?") {
    $a = @('-ApplyConfig'); if ($DryRun) { $a += '-DryRun' }
    Run "& `"$(Join-Path $Root 'plugins\dev-team\install.ps1')`" $($a -join ' ')"
  }
}

if (Ask "Install copilot-preset (route models through GitHub Copilot)?" 'N') {
  Plug 'copilot-preset' (Join-Path $Root 'plugins\copilot-preset')
  if (Ask "  Apply copilot-preset config?" 'N') {
    $a = @('-ApplyConfig'); if ($DryRun) { $a += '-DryRun' }
    Run "& `"$(Join-Path $Root 'plugins\copilot-preset\install.ps1')`" $($a -join ' ')"
  }
  Write-Host "  Reminder: run omp then /login -> GitHub Copilot."
}

if (Ask "Install token-diet (RTK + CodeGraph + caveman)?" 'N') {
  Plug 'token-diet' (Join-Path $Root 'plugins\token-diet')
  Ensure-Path (Join-Path $HOME ".local\bin")
  Write-Host "  Reminder: enable the codegraph MCP server once indexed."
}

if (Ask "Install azure-devops-fs (Azure DevOps as a filesystem)?" 'N') {
  Plug 'azure-devops-fs' (Join-Path $Root 'plugins\azure-devops-fs')
  if (Ask "  Configure Azure DevOps env vars now?" 'N') {
    $org  = Read-Host "    AZURE_DEVOPS_ORG"
    $proj = Read-Host "    AZURE_DEVOPS_PROJECT (optional)"
    $pat  = Read-Host "    AZURE_DEVOPS_PAT" -AsSecureString
    if ($DryRun) { Write-Host "  [dry-run] setx AZURE_DEVOPS_ORG/PROJECT/PAT" }
    else {
      if ($org)  { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_ORG', $org, 'User') }
      if ($proj) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PROJECT', $proj, 'User') }
      $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat))
      if ($plain) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', $plain, 'User'); Write-Host "  PAT stored in user environment." }
    }
  }
  Write-Host "  Reminder: enable the azure-devops MCP server (enabled:true) in your .mcp.json."
}

Bold "Done"
Say "Installed tools:"
foreach ($t in 'omp','rtk','codegraph','node') { if (Have $t) { Ok "$t -> $((Get-Command $t).Source)" } }
Write-Host "`nOpen a NEW shell so PATH changes take effect, then run: omp"
