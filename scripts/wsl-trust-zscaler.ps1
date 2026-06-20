#requires -Version 5.1
<#
  wsl-trust-zscaler.ps1 — install the corporate root CA (Zscaler by default) into
  a WSL distro's system trust store, from Windows. Run this from a WINDOWS
  PowerShell (powershell.exe), NOT from inside WSL. No sudo needed — it uses
  `wsl --user root` for the in-distro steps.

  After this runs, curl/git/node/bun/openssl inside WSL trust the corporate CA
  natively (no --insecure-tls, no per-tool env vars). This is the PROPER fix for
  TLS-intercepting proxies (Zscaler / Trend Micro) under WSL.

  Usage (from PowerShell on Windows):
    powershell.exe -ExecutionPolicy Bypass -File .\scripts\wsl-trust-zscaler.ps1
    # match a different CA / target a specific distro:
    .\scripts\wsl-trust-zscaler.ps1 -SubjectMatch '*Trend Micro*' -Distro Ubuntu

  Adapted from the known-good Zscaler-under-WSL recipe.
#>
[CmdletBinding()]
param(
  [string]$SubjectMatch = '*Zscaler Root CA*',
  [string]$Distro = ''                       # '' = default WSL distro
)
$ErrorActionPreference = 'Stop'

$wslArgs = @('--user', 'root')
if ($Distro) { $wslArgs = @('-d', $Distro) + $wslArgs }

Write-Host "Looking for a root CA whose subject matches '$SubjectMatch'..." -ForegroundColor Cyan
$certs = @(Get-ChildItem -Path Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -Recurse |
  Where-Object { $_.Subject -like $SubjectMatch })
if (-not $certs.Count) {
  throw "No certificate matching '$SubjectMatch' found in the Windows trust store. Is the proxy CA installed on Windows?"
}

# Export every matching cert (there can be more than one) to DER .cer in the
# Windows user profile, then convert + install each inside WSL.
$i = 0
foreach ($c in ($certs | Sort-Object Thumbprint -Unique)) {
  $i++
  $name = "corp-ca-$i"
  $cer  = Join-Path $env:USERPROFILE "$name.cer"
  Write-Host "  exporting [$($c.Subject)] -> $cer" -ForegroundColor Green
  Export-Certificate -Cert $c -Type CER -FilePath $cer | Out-Null

  $winUser = $env:UserName
  # Copy from the Windows profile into the distro, convert DER->PEM, drop into the
  # system trust dir, and refresh the bundle — all as root inside WSL.
  & wsl @wslArgs -e bash -c "cp '/mnt/c/Users/$winUser/$name.cer' /usr/local/share/ca-certificates/../ 2>/dev/null; cp '/mnt/c/Users/$winUser/$name.cer' /root/$name.cer"
  & wsl @wslArgs -e bash -c "openssl x509 -inform der -in /root/$name.cer -out /usr/local/share/ca-certificates/$name.crt && chmod 644 /usr/local/share/ca-certificates/$name.crt"
  Remove-Item $cer -ErrorAction SilentlyContinue
}

Write-Host "Refreshing the WSL CA bundle (update-ca-certificates)..." -ForegroundColor Cyan
& wsl @wslArgs -e bash -c "update-ca-certificates -f"

Write-Host "Done. The corporate CA is now trusted inside WSL. Re-open your WSL shell, then run the OMP installer normally (no --insecure-tls needed)." -ForegroundColor White
