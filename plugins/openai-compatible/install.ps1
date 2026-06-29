#requires -Version 5.1
<#
  openai-compatible installer (Windows) — register any OpenAI-compatible
  endpoint (LiteLLM, Ollama, vLLM, LocalAI, …) as a named provider in OMP.
  Prompts for the provider name, base URL, and API key (unless provided via
  flags/env), lists the models to confirm connectivity, and writes the provider
  into ~/.omp/agent/models.yml. The key is stored in ~/.omp/<name>.key and
  referenced from models.yml — never written inline or set in User env.
  Flags: -Name, -Url, -ApiKey, -NoConfig, -NoUpdate (no-op), -Yes.
#>
[CmdletBinding()]
param(
  [string]$Name   = $env:OAI_PROVIDER_NAME ?? 'litellm',
  [string]$Url    = $env:OAI_PROVIDER_URL,
  [string]$ApiKey = $env:OAI_PROVIDER_API_KEY,
  [switch]$NoConfig,
  [switch]$NoUpdate,
  [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
$Runner = if (Have bun) { 'bun' } elseif (Have node) { 'node' } else { Warn "bun/node not found — install OMP first"; return }

$ext = Join-Path $Here 'extensions\openai-provider.ts'

if (-not $Url -and -not $Yes) {
  $n = Read-Host "    Provider name (default: $Name)"
  if ($n) { $Name = $n }
  $Url = Read-Host '    Base URL (e.g. http://localhost:4000)'
}
if (-not $Url) { Say "No URL given — skipping provider config (set -Url and re-run)." }
if ($Url -and -not $ApiKey -and -not $Yes) {
  $sec = Read-Host '    API key (blank if none)' -AsSecureString
  $ApiKey = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

if ($Url) {
  Say "Listing models for provider '$Name' from $Url"
  $listArgs = @($ext, '--list', '--url', $Url); if ($ApiKey) { $listArgs += @('--api-key', $ApiKey) }
  try {
    $models = & $Runner @listArgs 2>$null
    if ($models) { $models | ForEach-Object { Write-Host "      - $_" } }
    else { Warn "no models listed — writing config anyway (OMP discovers at runtime)." }
  } catch { Warn "could not list models ($_). Writing config anyway." }

  if (-not $NoConfig) {
    $omp = Join-Path $HOME '.omp'; $keyFile = Join-Path $omp "$Name.key"
    $modelsYml = Join-Path $omp 'agent\models.yml'
    New-Item -ItemType Directory -Force -Path (Join-Path $omp 'agent') | Out-Null
    if ($ApiKey) {
      Set-Content -Path $keyFile -Value $ApiKey -NoNewline
      $apiRef = "`"!cat $keyFile`""
    } else {
      $apiRef = '""'
    }
    # Persist URL + name as User env vars so the extension registers live.
    # The API key is NEVER stored in env — only in the key file.
    [Environment]::SetEnvironmentVariable('OAI_PROVIDER_URL',  $Url,  'User')
    [Environment]::SetEnvironmentVariable('OAI_PROVIDER_NAME', $Name, 'User')

    if (-not (Test-Path $modelsYml)) { New-Item -ItemType File -Force -Path $modelsYml | Out-Null }
    $existingContent = Get-Content $modelsYml -Raw -ErrorAction SilentlyContinue
    if ($existingContent -match "^\s+${Name}:") {
      Say "Provider '$Name' already in $modelsYml — preserved."
    } else {
      $block = (& $Runner $ext '--yaml' '--name' $Name '--url' $Url '--api-key-ref' $apiRef) -join "`n"
      $lines = Get-Content $modelsYml
      $bak = "$modelsYml.bak"; Copy-Item -Force $modelsYml $bak
      if ($lines -match '^providers:\s*$') {
        $inner = ($block -split "`n" | Select-Object -Skip 1) -join "`n"
        $out = @()
        $done = $false
        foreach ($l in $lines) { $out += $l; if (-not $done -and $l -match '^providers:\s*$') { $out += $inner; $done = $true } }
        Set-Content -Path $modelsYml -Value $out
      } else {
        Add-Content -Path $modelsYml -Value "`n$block"
      }
      $py = Get-Command python3 -ErrorAction SilentlyContinue; if (-not $py) { $py = Get-Command python -ErrorAction SilentlyContinue }
      $hasYaml = $false
      if ($py) { & $py.Source -c 'import yaml' 2>$null | Out-Null; $hasYaml = ($LASTEXITCODE -eq 0) }
      if ($hasYaml) {
        & $py.Source -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' $modelsYml 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
          Remove-Item $bak -ErrorAction SilentlyContinue
          Say "Wrote the '$Name' provider to $modelsYml (validated)"
        } else {
          Move-Item -Force $bak $modelsYml
          Warn "Result was not valid YAML — restored $modelsYml from backup. Add the provider manually."
        }
      } else {
        Remove-Item $bak -ErrorAction SilentlyContinue
        Say "Wrote the '$Name' provider to $modelsYml (no YAML validator found — skipped validation)"
      }
    }
  }
}

# Mirror the extension into OMP's native dir.
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME '.omp\agent\extensions\openai-compatible'
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "openai-compatible provider extension loaded"
}
Say "openai-compatible ready. Restart omp; reference models as '$Name/<model-id>' in modelRoles. Re-list with /oai-provider."
