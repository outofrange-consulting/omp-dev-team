#requires -Version 5.1
<#
  cliproxy installer (Windows) — register a CLIProxyAPI gateway as an
  OpenAI-compatible model provider in OMP. Prompts for the gateway URL + API key
  (unless provided via flags/env), lists the models to confirm connectivity, and
  writes the provider into ~/.omp/agent/models.yml. The key is stored in
  ~/.omp/cliproxy.key and referenced from models.yml.
  Flags: -Url, -ApiKey, -NoConfig, -NoUpdate (no-op), -Yes.
#>
[CmdletBinding()]
param([string]$Url = $env:CLIPROXY_URL, [string]$ApiKey = $env:CLIPROXY_API_KEY, [switch]$NoConfig, [switch]$NoUpdate, [switch]$Yes)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Bun-Run ($argList) {
  if (Have bun) { return (& bun @argList) }
  if (Have node) { return (& node @argList) }
  throw "no bun/node"
}
$Runner = if (Have bun) { 'bun' } elseif (Have node) { 'node' } else { Warn "bun/node not found — install OMP first"; return }

$ext = Join-Path $Here 'extensions\cliproxy.ts'

if (-not $Url -and -not $Yes) { $Url = Read-Host '    CLIProxyAPI gateway URL (e.g. http://localhost:8317)' }
if (-not $Url) { Say "No gateway URL — skipping provider config (set -Url and re-run)." }
if ($Url -and -not $ApiKey -and -not $Yes) {
  $sec = Read-Host '    API key (blank if none)' -AsSecureString
  $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

if ($Url) {
  Say "Listing models from $Url"
  $listArgs = @($ext, '--list', '--url', $Url); if ($ApiKey) { $listArgs += @('--api-key', $ApiKey) }
  try {
    $models = & $Runner @listArgs 2>$null
    if ($models) { $models | ForEach-Object { Write-Host "      - $_" } }
    else { Warn "no models listed — writing config anyway (OMP discovers at runtime)." }
  } catch { Warn "could not list models ($_). Writing config anyway." }

  if (-not $NoConfig) {
    $omp = Join-Path $HOME '.omp'; $keyFile = Join-Path $omp 'cliproxy.key'
    $modelsYml = Join-Path $omp 'agent\models.yml'
    New-Item -ItemType Directory -Force -Path (Join-Path $omp 'agent') | Out-Null
    if ($ApiKey) {
      Set-Content -Path $keyFile -Value $ApiKey -NoNewline
      $apiRef = "`"!cat $keyFile`""
      [Environment]::SetEnvironmentVariable('CLIPROXY_URL', $Url, 'User')
      [Environment]::SetEnvironmentVariable('CLIPROXY_API_KEY', $ApiKey, 'User')
    } else {
      $apiRef = '""'
      [Environment]::SetEnvironmentVariable('CLIPROXY_URL', $Url, 'User')
    }
    if (-not (Test-Path $modelsYml)) { New-Item -ItemType File -Force -Path $modelsYml | Out-Null }
    if ((Get-Content $modelsYml) -match '^\s+cliproxy:') {
      Say "Provider 'cliproxy' already in $modelsYml — preserved."
    } else {
      $block = (& $Runner $ext '--yaml' '--url' $Url '--api-key-ref' $apiRef) -join "`n"
      $lines = Get-Content $modelsYml
      if ($lines -match '^providers:\s*$') {
        $inner = ($block -split "`n" | Select-Object -Skip 1) -join "`n"
        $out = @()
        $done = $false
        foreach ($l in $lines) { $out += $l; if (-not $done -and $l -match '^providers:\s*$') { $out += $inner; $done = $true } }
        Set-Content -Path $modelsYml -Value $out
      } else {
        Add-Content -Path $modelsYml -Value "`n$block"
      }
      Say "Wrote the cliproxy provider to $modelsYml"
    }
  }
}

# Mirror the extension into OMP's native dir.
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME '.omp\agent\extensions\cliproxy'
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "cliproxy provider extension loaded"
}
Say "cliproxy ready. Restart omp; reference models as 'cliproxy/<model-id>' in modelRoles. Re-list with /cliproxy."
