#requires -Version 5.1
<#
  omp-dev-team for GitHub Copilot CLI — global installer (Windows).

  Installs the GitHub Copilot CLI, then interactively offers each component of the
  chain — you check the ones you want:

    * dev-team   — orchestrator + workflow/critic agents, blocking guard hooks
                   (plan-gate, path/freeze/spec/destructive/review-gate), the `dt`
                   gate CLI, and the operating-manual copilot-instructions.
    * token-diet — ctx-wire (shell-output compression + secret scrub), the
                   codebase-memory-mcp MCP server, and a postToolUse output
                   compressor; caveman/yagni discipline.
    * datadog    — the Datadog `pup` CLI + a `datadog` agent.

  Everything is brought UP TO DATE by default. Your Copilot config (mcp-config.json,
  agents) is MERGED, never clobbered.

  Flags:
    -Yes          non-interactive: install all components
    -NoUpdate     keep tools already installed (don't refresh)
    -NoRuntimes   skip installing Node (assume Node >= 22 is present)
    -NoConfig     don't write/merge ~/.copilot config
    -NoArm        don't offer to arm the dev-team guards in the current repo
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$NoRuntimes, [switch]$NoUpdate, [switch]$NoConfig, [switch]$NoArm)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($env:COPILOT_HOME) { $CopilotHome = $env:COPILOT_HOME } else { $CopilotHome = Join-Path $HOME '.copilot' }

function Bold ($m) { Write-Host "`n$m" -ForegroundColor White }
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }
function Ask ($q, $def = 'Y') {
  if ($Yes) { return $true }
  $hint = if ($def -eq 'Y') { '[Y/n]' } else { '[y/N]' }
  $ans = Read-Host "$q $hint"
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $def }
  return ($ans -match '^(y|Y)')
}
function Ensure-Path ($dir) {
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (";$env:Path;" -like "*;$dir;*") { return }
  $env:Path = "$dir;$env:Path"
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  if (";$u;" -notlike "*;$dir;*") { [Environment]::SetEnvironmentVariable('Path', "$u;$dir", 'User') }
}
function Node-Version {
  if (-not (Have node)) { return '0' }
  return ((node --version) -replace '^v','')
}
function Version-Ge ($a, $b) {
  try { return ([version]$a -ge [version]$b) } catch { return $false }
}

Bold "omp-dev-team for GitHub Copilot CLI"
Write-Host "Repo: $Root"
Write-Host "Copilot home: $CopilotHome"

# --- 0) Node >= 22 ----------------------------------------------------------
$MinNode = '22.0.0'
if (-not $NoRuntimes) {
  if ((Have node) -and (Version-Ge (Node-Version) $MinNode) -and $NoUpdate) { Ok "node $(node --version)" }
  elseif ((Have node) -and (Version-Ge (Node-Version) $MinNode)) { Ok "node $(node --version)" }
  else {
    Say "Installing Node.js (LTS, >= $MinNode)"
    if (Have winget) { Run "winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements" }
    else { Warn "could not install Node.js automatically — install Node >= $MinNode from https://nodejs.org" }
  }
} else { Say "Skipping runtime install (-NoRuntimes)" }
Ensure-Path (Join-Path $HOME '.local\bin')

# --- 1) GitHub Copilot CLI --------------------------------------------------
if ((Have copilot) -and $NoUpdate) { Ok "copilot present ($(copilot --version 2>$null | Select-Object -First 1))" }
else {
  if (Have copilot) { Say "Updating GitHub Copilot CLI" } else { Say "Installing GitHub Copilot CLI" }
  if (Have npm) { Run "npm install -g `@github/copilot`@latest" }
  elseif (Have winget) { Run "winget install GitHub.Copilot -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "need npm or winget to install Copilot CLI — see https://docs.github.com/copilot/how-tos/set-up/install-copilot-cli" }
}
if (-not (Have copilot)) { Warn "copilot not on PATH yet — open a new shell after this" }

$env:COPILOT_HOME = $CopilotHome
$common = @()
if ($NoUpdate) { $common += '-NoUpdate' }
if ($NoConfig) { $common += '-NoConfig' }
if ($Yes)      { $common += '-Yes' }

function Pack ($name, $dir) {
  $ps1 = Join-Path $dir 'install.ps1'
  if (-not (Test-Path $ps1)) { Warn "$name: no install.ps1"; return }
  Say "Installing component: $name"
  Run "& `"$ps1`" $($common -join ' ')"
}

# --- 2) Per-component checkboxes --------------------------------------------
Bold "Components — check the ones you want"
$SEL_DEVTEAM = $false; $SEL_TOKENDIET = $false; $SEL_DATADOG = $false

if (Ask "Install dev-team (agentic pipeline: agents + blocking guard hooks + the dt gate CLI)?") {
  Pack 'dev-team' (Join-Path $Root 'packs\dev-team'); $SEL_DEVTEAM = $true
}
if (Ask "Install token-diet (ctx-wire + codebase-memory-mcp + output-compression hook)?") {
  Pack 'token-diet' (Join-Path $Root 'packs\token-diet'); $SEL_TOKENDIET = $true
}
if (Ask "Install datadog (pup CLI + datadog agent)?" 'N') {
  Pack 'datadog' (Join-Path $Root 'packs\datadog'); $SEL_DATADOG = $true
}

# --- 3) Offer to arm the dev-team guards in the current repo -----------------
if ($SEL_DEVTEAM -and -not $NoArm -and (Have node)) {
  if ((Test-Path '.git') -and (Ask "Arm the dev-team guards in the CURRENT repo ($(Get-Location))? (writes .github\hooks + .github\copilot-instructions.md)" 'N')) {
    Run "node `"$CopilotHome\dev-team\dt.mjs`" init ."
  } else {
    Write-Host "  Skipped. Arm any repo later with: dt init  (run from inside that repo)"
  }
}

# --- 4) Doctor --------------------------------------------------------------
Bold "Doctor"
Ensure-Path (Join-Path $HOME '.local\bin')
$fail = $false
function Check ($t, $req, $vc) {
  if (Have $t) {
    $v = ''; if ($vc) { try { $v = (Invoke-Expression $vc 2>$null | Select-Object -First 1) } catch {} }
    Ok ("{0} {1}-> {2}" -f $t, $(if ($v) { "($v) " } else { '' }), (Get-Command $t).Source)
  } elseif ($req -eq 'required') { Warn "$t MISSING (required)"; $script:fail = $true }
  else { Warn "$t not found (optional)" }
}
Check git     'required' 'git --version'
Check node    'required' 'node --version'
Check copilot 'required' 'copilot --version'
if ($SEL_DEVTEAM)  { Check dt  'optional' 'dt help' }
if ($SEL_TOKENDIET){ Check ctx-wire 'optional' 'ctx-wire --version'; Check codebase-memory-mcp 'optional' 'codebase-memory-mcp --version' }
if ($SEL_DATADOG)  { Check pup 'optional' 'pup --version' }

if (-not $NoConfig) {
  $agentsDir = Join-Path $CopilotHome 'agents'
  if (Test-Path $agentsDir) { Write-Host "  agents installed:"; Get-ChildItem "$agentsDir\*.agent.md" | ForEach-Object { Write-Host "    $($_.Name)" } }
  $mcp = Join-Path $CopilotHome 'mcp-config.json'
  if (Test-Path $mcp) { Ok "mcp-config.json present ($mcp)" }
}

Write-Host ""
if (-not $fail) { Bold "All set" } else { Bold "Finished with warnings — see above" }
Write-Host "Open a NEW shell so PATH changes persist, then run: copilot"
Write-Host "First run: /login (GitHub Copilot). Pick a model with /model. Use agents with /agent <name>."
if ($SEL_DEVTEAM) { Write-Host "Dev-team flow: dt scope -> /agent plan -> dt plan-approve -> /agent build -> /agent review -> dt review-approve -> /agent pr" }
if ($fail) { exit 1 }
