#requires -Version 5.1
<#
  omp-dev-team — global installer (Windows).
  Installs OMP, registers this marketplace, then interactively offers each plugin
  and its config. Updates the user PATH so everything works in new shells.
  Flags:
    -Yes          non-interactive: install all plugins + apply default configs
    -Update       refresh things already installed (otherwise: skip them)
    -NoRuntimes   skip installing node/bun/cargo (assume they're present)
    -DryRun       print actions without executing

  Already-present policy: SKIP by default (idempotent, never asks). Pass -Update
  to refresh to latest. Exception: bun is upgraded if below the version OMP needs.
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$DryRun, [switch]$NoRuntimes, [switch]$Update)
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

$MinBun = [version]'1.3.14'
function Ensure-Bun {
  $okv = $false
  if (Have bun) { try { $okv = ([version]((bun --version).Trim()) -ge $MinBun) } catch {} }
  if ($okv -and -not $Update) { Ok "bun $(bun --version) (skip; -Update to refresh)" }
  else {
    Say "Installing bun (>= $MinBun; OMP requires it)"
    if (Have winget) { Run "winget install --id Oven-sh.Bun -e --accept-source-agreements --accept-package-agreements" }
    else { Run "irm https://bun.sh/install.ps1 | iex" }
  }
  Ensure-Path (Join-Path $HOME ".bun\bin")
}
function Ensure-Node {
  if ((Have node) -and -not $Update) { Ok "node $(node --version) (skip; -Update to refresh)"; return }
  Say "Installing Node.js (LTS)"
  if (Have winget) { Run "winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "could not install Node.js automatically — see https://nodejs.org" }
}
function Ensure-Cargo {
  if ((Have cargo) -and -not $Update) { Ok "cargo $((cargo --version) -split ' ' | Select-Object -Index 1) (skip; -Update to refresh)"; return }
  if ((Have rustup) -and $Update) { Say "Updating Rust"; Run "rustup update"; return }
  if (Have cargo) { Ok "cargo present"; return }
  Say "Installing Rust (rustup)"
  if (Have winget) { Run "winget install --id Rustlang.Rustup -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "install Rust from https://rustup.rs" }
  Ensure-Path (Join-Path $HOME ".cargo\bin")
}

Bold "omp-dev-team installer"
Write-Host "Repo: $Root"

# --- 0) Runtimes (node, bun, cargo) ----------------------------------------
if (-not $NoRuntimes) { Say "Ensuring runtimes"; Ensure-Bun; Ensure-Node; Ensure-Cargo }
else { Say "Skipping runtime install (-NoRuntimes)" }

# --- 1) OMP ----------------------------------------------------------------
if ((Have omp) -and -not $Update) { Ok "omp present ($(omp --version 2>$null)) (skip; -Update to refresh)" }
elseif (Have omp) { Say "Updating OMP"; Run "bun add -g @oh-my-pi/pi-coding-agent@latest" }
else { Say "Installing OMP (latest)"; Run "irm https://omp.sh/install.ps1 | iex" }
Ensure-Path (Join-Path $HOME ".local\bin")
if (-not (Have omp)) { Warn "omp not on PATH yet — open a new shell after this" }

# --- 2) Register the marketplace -------------------------------------------
if (Have omp) { Say "Registering marketplace ($Market) from local checkout"; Run "omp plugin marketplace add `"$Root`"" }

# Already-installed policy: SKIP by default; with -Update, reinstall (--force).
function Plug ($name, $dir) {
  if (Have omp) {
    $installed = (omp plugin list 2>$null | Select-String "$name@$Market")
    if ($installed) {
      if ($Update) { Run "omp plugin install --force $name@$Market" } else { Ok "plugin $name already installed (skip; -Update to refresh)" }
    } else { Run "omp plugin install $name@$Market" }
  }
  $ps1 = Join-Path $dir 'install.ps1'
  if (Test-Path $ps1) {
    $a = @(); if ($DryRun) { $a += '-DryRun' }; if ($Update -and $name -eq 'token-diet') { $a += '-Update' }
    Run "& `"$ps1`" $($a -join ' ')"
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

# --- 4) Doctor -------------------------------------------------------------
Bold "Doctor"
if ($DryRun) { Write-Host "(dry-run — skipping verification)"; return }
$fail = $false
function Check ($t, $req, $vc) {
  if (Have $t) {
    $v = ''; if ($vc) { try { $v = (Invoke-Expression $vc 2>$null | Select-Object -First 1) } catch {} }
    Ok ("{0} {1}-> {2}" -f $t, $(if ($v) { "($v) " } else { '' }), (Get-Command $t).Source)
  } elseif ($req -eq 'required') { Warn "$t MISSING (required)"; $script:fail = $true }
  else { Warn "$t not found (optional)" }
}
Check git       'required'    'git --version'
Check bun       'required'    'bun --version'
Check node      'recommended' 'node --version'
Check cargo     'recommended' 'cargo --version'
Check omp       'required'    'omp --version'
Check rtk       'optional'    'rtk --version'
Check codegraph 'optional'    'codegraph --version'

Bold "OMP launch check"
if ((Have omp) -and (omp --version 2>$null)) {
  Ok "omp launches: $(omp --version 2>$null | Select-Object -First 1)"
  Write-Host "  plugins installed:"; (omp plugin list 2>$null | Select-String "@$Market") | ForEach-Object { Write-Host "    $_" }
} else { Warn "omp did not launch — ensure $HOME\.bun\bin is on PATH"; $script:fail = $true }

Write-Host ""
if (-not $fail) { Bold "All set" } else { Bold "Finished with warnings — see above" }
Write-Host "Open a NEW shell so PATH changes persist, then run: omp"
if ($fail) { exit 1 }
