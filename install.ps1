#requires -Version 5.1
<#
  omp-dev-team — global installer (Windows).
  Installs OMP, registers this marketplace, then interactively offers each plugin
  and its config. Updates the user PATH so everything works in new shells.
  Flags:
    -Yes          non-interactive: install all plugins + reset config
    -Update       also refresh bun/node/omp (tools), not just plugins/config
    -NoRuntimes   skip installing bun/node (assume they're present)
    -NoConfig     don't write/reset ~/.omp/agent/config.yml (keep yours as-is)
    -DryRun       print actions without executing

  DEFAULT: works out of the box. Plugins are reinstalled to latest and the managed
  model-roles/skills block in your OMP config is RESET (old config backed up first).
  Tools already present are kept (-Update also refreshes them). -NoConfig keeps your config.
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$DryRun, [switch]$NoRuntimes, [switch]$Update, [switch]$NoConfig)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Market = 'omp-dev-team'
$OnWindows = ($IsWindows -or $env:OS -eq 'Windows_NT')

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
  if ($OnWindows) { Ok "bun not required on Windows (OMP ships a native .exe)"; return }
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

Bold "omp-dev-team installer"
Write-Host "Repo: $Root"

# --- 0) Runtimes (bun, node) -----------------------------------------------
if (-not $NoRuntimes) { Say "Ensuring runtimes"; Ensure-Bun; Ensure-Node }
else { Say "Skipping runtime install (-NoRuntimes)" }

# --- 1) OMP ----------------------------------------------------------------
if ((Have omp) -and -not $Update) { Ok "omp present ($(omp --version 2>$null)) (skip; -Update to refresh)" }
elseif (Have omp) { Say "Updating OMP"; Run "bun add -g @oh-my-pi/pi-coding-agent@latest" }
else { Say "Installing OMP (latest)"; Run "irm https://omp.sh/install.ps1 | iex" }
# Tool install dirs (so omp + co. are found now and in new shells).
Ensure-Path (Join-Path $HOME ".local\bin")
if ($OnWindows) {
  Ensure-Path (Join-Path $env:LOCALAPPDATA 'omp')                      # omp.exe lands here
  Ensure-Path (Join-Path $env:LOCALAPPDATA 'codegraph\current\bin')    # codegraph
} else {
  Ensure-Path (Join-Path $HOME '.bun\bin')
}
if (-not (Have omp)) { Warn "omp not on PATH yet — open a new shell after this" }

# --- 2) Register the marketplace -------------------------------------------
if (Have omp) { Say "Registering marketplace ($Market) from local checkout"; Run "omp plugin marketplace add `"$Root`"" }

# OMP does NOT load extension modules (package.json omp.extensions) from
# marketplace cache installs — only from npm/linked plugins or the native
# extension dirs. Mirror a plugin's extension modules into the user native dir
# (~/.omp/agent/extensions/<name>/) so its tool/guard/provider actually loads.
function Install-Extensions ($name, $dir) {
  $src = Join-Path $dir 'extensions'
  if (-not (Test-Path $src)) { return }
  $dest = Join-Path $HOME ".omp\agent\extensions\$name"
  if ($DryRun) { Write-Host "  [dry-run] mirror $name extensions -> $dest (OMP native ext dir)"; return }
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $dir 'package.json'
  if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }   # carries omp.extensions
  Ok "$name extension loaded into $dest"
}

# Plugins are always reinstalled (--force) so installed content is current.
function Plug ($name, $dir) {
  if (Have omp) { Run "omp plugin install --force $name@$Market" }
  Install-Extensions $name $dir
  $ps1 = Join-Path $dir 'install.ps1'
  if (Test-Path $ps1) {
    $a = @(); if ($DryRun) { $a += '-DryRun' }
    if ($Update -and $name -eq 'token-diet') { $a += '-Update' }
    if ($name -eq 'token-diet') { $a += '-NoConfig' }  # global Write-Config owns config.yml
    if ($Yes -and ($name -eq 'token-diet' -or $name -eq 'azure-devops-fs')) { $a += '-Yes' }
    Run "& `"$ps1`" $($a -join ' ')"
  }
}

# Compose + RESET the managed model-roles/skills block so an install works out of
# the box. Backs up the old config first. -NoConfig skips.
function Write-Config {
  if ($NoConfig) { Say "Keeping your OMP config as-is (-NoConfig)"; return }
  if (-not ($SEL_DEVTEAM -or $SEL_COPILOT -or $SEL_TOKENDIET)) { return }
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  Bold "OMP config"; Say "Resetting model roles + skills in $cfg (out-of-the-box defaults)"
  if ($DryRun) { Write-Host "  [dry-run] back up $cfg then write the managed block"; return }
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if ((Test-Path $cfg) -and (Get-Item $cfg).Length -gt 0) { $b = "$cfg.$((Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')).bak"; Copy-Item $cfg $b; Warn "previous config backed up to $b" }
  $lines = @("# Managed by omp-dev-team install.ps1 — re-run to regenerate (old config backed up).")
  if ($SEL_COPILOT) {
    $lines += "# Models via GitHub Copilot. Run omp -> /login -> GitHub Copilot first.",
      "enabledModels: [github-copilot/*]", "modelProviderOrder: [github-copilot]", "modelRoles:",
      "  smol: github-copilot/claude-haiku-4.5", "  task: github-copilot/claude-haiku-4.5",
      "  default: github-copilot/claude-sonnet-4.6", "  plan: github-copilot/claude-sonnet-4.6",
      "  slow: github-copilot/claude-opus-4.8"
  } elseif ($SEL_DEVTEAM) {
    $lines += "modelRoles:", "  smol: claude-haiku-4-5", "  task: claude-haiku-4-5",
      "  default: claude-sonnet-4-6", "  plan: claude-sonnet-4-6", "  slow: claude-opus-4-8"
  }
  if ($SEL_DEVTEAM -or $SEL_TOKENDIET) { $lines += "skills:", "  enabled: true", "  enableSkillCommands: true" }
  if ($SEL_DEVTEAM) { $lines += "task:", "  maxRecursionDepth: 4", "  simple: default" }
  Set-Content -Path $cfg -Value $lines
  Ok "Wrote $cfg (default=Sonnet 4.6 orchestrator; smol/task=Haiku; slow=Opus)"
}

# --- 3) Per-plugin prompts --------------------------------------------------
Bold "Plugins"
$SEL_DEVTEAM = $false; $SEL_COPILOT = $false; $SEL_TOKENDIET = $false

if (Ask "Install dev-team (agentic dev team: /specs -> /plan -> /build -> /pr)?") {
  Plug 'dev-team' (Join-Path $Root 'plugins\dev-team'); $SEL_DEVTEAM = $true
}

if (Ask "Install copilot-preset (route models through GitHub Copilot)?") {
  Plug 'copilot-preset' (Join-Path $Root 'plugins\copilot-preset'); $SEL_COPILOT = $true
  Write-Host "  Reminder: run omp then /login -> GitHub Copilot."
}

if (Ask "Install token-diet (ctx-wire + CodeGraph + caveman + yagni)?") {
  Plug 'token-diet' (Join-Path $Root 'plugins\token-diet'); $SEL_TOKENDIET = $true
  Ensure-Path (Join-Path $HOME ".local\bin")
}

if (Ask "Install local-llm (run roles on local GPU models; needs >=8GB VRAM)?" 'N') {
  Plug 'local-llm' (Join-Path $Root 'plugins\local-llm')
}

if (Ask "Install azure-devops-fs (Azure DevOps as a filesystem)?" 'N') {
  # The plugin installer ensures Node, pre-warms the MCP server, and (when
  # interactive) prompts for the org/project/PAT and persists them.
  Plug 'azure-devops-fs' (Join-Path $Root 'plugins\azure-devops-fs')
  Write-Host "  Reminder: enable the azure-devops MCP server (enabled:true) in your .mcp.json."
}

# Compose + reset the OMP config so the selected plugins work out of the box.
Write-Config

# --- 4) Doctor -------------------------------------------------------------
Bold "Doctor"
if ($DryRun) { Write-Host "(dry-run — skipping verification)"; return }
# Refresh PATH for dirs created during plugin installs.
foreach ($d in @((Join-Path $HOME '.local\bin'), (Join-Path $HOME '.bun\bin'))) { Ensure-Path $d }
if ($OnWindows) { foreach ($d in @((Join-Path $env:LOCALAPPDATA 'omp'), (Join-Path $env:LOCALAPPDATA 'codegraph\current\bin'))) { Ensure-Path $d } }
$fail = $false
function Check ($t, $req, $vc) {
  if (Have $t) {
    $v = ''; if ($vc) { try { $v = (Invoke-Expression $vc 2>$null | Select-Object -First 1) } catch {} }
    Ok ("{0} {1}-> {2}" -f $t, $(if ($v) { "($v) " } else { '' }), (Get-Command $t).Source)
  } elseif ($req -eq 'required') { Warn "$t MISSING (required)"; $script:fail = $true }
  else { Warn "$t not found (optional)" }
}
Check git       'required'    'git --version'
Check bun       $(if ($OnWindows) { 'optional' } else { 'required' }) 'bun --version'
Check node      'recommended' 'node --version'
Check omp       'required'    'omp --version'
Check ctx-wire  'optional'    'ctx-wire --version'
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
