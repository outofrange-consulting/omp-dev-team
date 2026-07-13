#requires -Version 5.1
<#
  datadog component installer (Copilot CLI, Windows).
  Installs the Datadog `pup` CLI, sets up auth, and installs the `datadog` agent
  into ~/.copilot/agents. Flags: -Yes -NoUpdate -NoConfig
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
function Run  ($cmd) { Invoke-Expression $cmd }

# --- install pup ------------------------------------------------------------
if ((Have pup) -and $NoUpdate) { Say "pup present ($(pup --version 2>$null | Select-Object -First 1))" }
else {
  Say "Installing Datadog pup CLI"
  if (Have scoop) { try { Run "scoop install pup" } catch {} }
  if (-not (Have pup) -and (Have winget)) { try { Run "winget install DataDog.pup -e --accept-source-agreements --accept-package-agreements" } catch {} }
  if (-not (Have pup)) {
    # Prebuilt release zip -> ~/.local/bin (no admin).
    $bin = Join-Path $HOME '.local\bin'; New-Item -ItemType Directory -Force -Path $bin | Out-Null
    try {
      $rel = Invoke-RestMethod 'https://api.github.com/repos/DataDog/pup/releases/latest'
      $ver = ($rel.tag_name -replace '^v','')
      $arch = if ([Environment]::Is64BitOperatingSystem) { 'x86_64' } else { 'i386' }
      $url = "https://github.com/DataDog/pup/releases/download/v$ver/pup_${ver}_Windows_$arch.zip"
      $tmp = New-TemporaryFile; $zip = "$($tmp.FullName).zip"
      Say "Downloading pup $ver ($arch)"
      Invoke-WebRequest -Uri $url -OutFile $zip
      $ex = Join-Path ([IO.Path]::GetTempPath()) ("pup-" + [Guid]::NewGuid())
      Expand-Archive -Path $zip -DestinationPath $ex -Force
      $exe = Get-ChildItem -Path $ex -Recurse -Filter 'pup.exe' | Select-Object -First 1
      if ($exe) { Copy-Item -Force $exe.FullName (Join-Path $bin 'pup.exe'); Ok "pup installed -> $bin\pup.exe" }
      else { Warn "pup.exe not found in the release archive" }
      Remove-Item $zip, $ex -Recurse -Force -ErrorAction SilentlyContinue
    } catch { Warn "pup download failed — install from https://github.com/DataDog/pup/releases" }
    if (";$env:Path;" -notlike "*;$bin;*") { $env:Path = "$bin;$env:Path" }
  }
}

# --- auth -------------------------------------------------------------------
if (-not $NoConfig -and (Have pup)) {
  $authed = $false; try { pup auth status *> $null; $authed = ($LASTEXITCODE -eq 0) } catch {}
  if ($authed) { Say "Datadog already authenticated" }
  elseif ($env:DD_API_KEY -or $env:DD_ACCESS_TOKEN) { Say "Datadog credentials present in environment" }
  elseif ($Yes) { Say "Skipping auth (non-interactive). Later: 'pup auth login' or set DD_API_KEY/DD_APP_KEY/DD_SITE." }
  else {
    if ((Read-Host "    Authenticate now via browser (pup auth login)? [Y/n]") -notmatch '^(n|N)') {
      try { Run "pup auth login" } catch { Warn "pup auth login failed — set DD_API_KEY/DD_APP_KEY instead." }
    }
  }
}

# --- agent -> ~/.copilot/agents ---------------------------------------------
if (-not $NoConfig) {
  $agents = Join-Path $CopilotHome 'agents'
  New-Item -ItemType Directory -Force -Path $agents | Out-Null
  Copy-Item -Force (Join-Path $Here 'agents\*.agent.md') $agents
  Ok "datadog agent installed -> $agents"
}

Say "datadog ready. In Copilot CLI: /agent datadog. Auth: 'pup auth login' or DD_API_KEY/DD_APP_KEY/DD_SITE."
