#requires -Version 5.1
<#
  datadog installer (Windows) — install the Datadog "pup" CLI
  (https://github.com/DataDog/pup) and set up authentication. The single OMP
  `datadog` skill drives pup, so we DON'T install ~30 separate skills by default
  — pass -WithSkills to also run `pup skills install pi`.
  Flags: -WithSkills, -NoConfig, -NoUpdate, -Yes.
#>
[CmdletBinding()]
param([switch]$WithSkills, [switch]$NoConfig, [switch]$NoUpdate, [switch]$Yes)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

$binDir = Join-Path $HOME '.local\bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null
if (";$env:Path;" -notlike "*;$binDir;*") { $env:Path = "$binDir;$env:Path" }

function Install-Pup {
  if ((Have pup) -and $NoUpdate) { Say "pup present ($(pup --version 2>$null))"; return }
  if (Have winget) {
    Say "Trying winget for pup"
    winget install --id DataDog.pup -e --accept-source-agreements --accept-package-agreements 2>$null
    if (Have pup) { return }
  }
  try {
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x86_64' } else { 'x86_64' }
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/DataDog/pup/releases/latest' -Headers @{ 'User-Agent' = 'omp-dev-team' }
    $ver = ($rel.tag_name -replace '^v', '')
    $url = "https://github.com/DataDog/pup/releases/download/v$ver/pup_${ver}_Windows_$arch.zip"
    Say "Installing pup $ver (Windows/$arch) to $binDir"
    $tmp = New-TemporaryFile; $zip = "$($tmp.FullName).zip"
    Invoke-WebRequest -Uri $url -OutFile $zip
    $dest = Join-Path $env:TEMP "pup-$ver"
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    $exe = Get-ChildItem -Path $dest -Recurse -Filter 'pup.exe' | Select-Object -First 1
    if ($exe) { Copy-Item -Force $exe.FullName (Join-Path $binDir 'pup.exe'); Say "pup installed" }
    else { Warn "pup.exe not found in the release archive" }
    Remove-Item $zip, $dest -Recurse -Force -ErrorAction SilentlyContinue
  } catch { Warn "pup install failed: $_ — see https://github.com/DataDog/pup/releases" }
}
Install-Pup

# --- authentication ---------------------------------------------------------
if (-not $NoConfig -and (Have pup)) {
  $authed = $false; try { pup auth status *> $null; $authed = ($LASTEXITCODE -eq 0) } catch {}
  if ($authed -or $env:DD_API_KEY -or $env:DD_ACCESS_TOKEN) { Say "Datadog already authenticated / credentials present" }
  elseif ($Yes) { Say "Skipping auth (non-interactive). Later: 'pup auth login' or set DD_API_KEY/DD_APP_KEY/DD_SITE." }
  else {
    $ans = Read-Host "    Authenticate now via browser (pup auth login)? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(y|Y)') {
      try { pup auth login } catch { Warn "pup auth login failed — set DD_API_KEY/DD_APP_KEY instead." }
    } else {
      $site = Read-Host "    DD_SITE [datadoghq.com]"; if (-not $site) { $site = 'datadoghq.com' }
      $key  = Read-Host "    DD_API_KEY" -AsSecureString
      $app  = Read-Host "    DD_APP_KEY" -AsSecureString
      $keyP = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($key))
      $appP = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($app))
      [Environment]::SetEnvironmentVariable('DD_SITE', $site, 'User')
      if ($keyP) { [Environment]::SetEnvironmentVariable('DD_API_KEY', $keyP, 'User') }
      if ($appP) { [Environment]::SetEnvironmentVariable('DD_APP_KEY', $appP, 'User') }
      Say "Datadog credentials saved to your user environment."
    }
  }
}

if ($WithSkills -and (Have pup)) {
  Say "Installing Datadog skills for OMP (pup skills install pi)"
  try { pup skills install pi } catch { Warn "pup skills install pi failed — the datadog skill still works via the CLI." }
}

Say "datadog ready. Restart omp and use the 'datadog' skill (it drives the pup CLI)."
