#requires -Version 5.1
<#
  dev-team component installer (Copilot CLI, Windows).
  Installs agents into ~/.copilot/agents, the hook scripts + dt CLI into
  ~/.copilot/dev-team, and a `dt.cmd` shim into ~/.local/bin. Guards are armed
  PER REPO with `dt init`. Flags: -Yes -NoUpdate -NoConfig
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$NoUpdate, [switch]$NoConfig)
$ErrorActionPreference = 'Stop'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($env:COPILOT_HOME) { $CopilotHome = $env:COPILOT_HOME } else { $CopilotHome = Join-Path $HOME '.copilot' }
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

if (-not (Have node)) { Warn "node not found — Copilot CLI + the dev-team hooks need Node >= 22." }

# --- agents -> ~/.copilot/agents -------------------------------------------
if (-not $NoConfig) {
  $agents = Join-Path $CopilotHome 'agents'
  Say "Installing dev-team agents into $agents"
  New-Item -ItemType Directory -Force -Path $agents | Out-Null
  Copy-Item -Force (Join-Path $Here 'agents\*.agent.md') $agents
  Ok "$((Get-ChildItem (Join-Path $Here 'agents\*.agent.md')).Count) agents installed"
}

# --- runtime -> ~/.copilot/dev-team ----------------------------------------
$Dest = Join-Path $CopilotHome 'dev-team'
Say "Installing dev-team runtime into $Dest"
if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'hooks\scripts') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'instructions') | Out-Null
Copy-Item -Force (Join-Path $Here 'dt.mjs') (Join-Path $Dest 'dt.mjs')
Copy-Item -Force (Join-Path $Here 'hooks\scripts\*.mjs') (Join-Path $Dest 'hooks\scripts')
Copy-Item -Force (Join-Path $Here 'instructions\*.md') (Join-Path $Dest 'instructions')
Ok "dt CLI + preToolUse guard + operating manual installed"

# --- dt.cmd shim -> ~/.local/bin -------------------------------------------
$bin = Join-Path $HOME '.local\bin'
New-Item -ItemType Directory -Force -Path $bin | Out-Null
$dtMjs = Join-Path $Dest 'dt.mjs'
Set-Content -Path (Join-Path $bin 'dt.cmd') -Value "@node `"$dtMjs`" %*" -Encoding ascii
Ok "dt -> $bin\dt.cmd"
if (";$env:Path;" -notlike "*;$bin;*") {
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  if (";$u;" -notlike "*;$bin;*") { [Environment]::SetEnvironmentVariable('Path', "$u;$bin", 'User') }
  $env:Path = "$bin;$env:Path"
}

Say "dev-team ready. Arm a repo: cd into it and run 'dt init'."
Write-Host "    Flow: dt scope -> /agent plan -> dt plan-approve -> /agent build -> /agent review -> dt review-approve -> /agent pr"
