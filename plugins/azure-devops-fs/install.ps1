#requires -Version 5.1
<#
  azure-devops-fs installer (Windows) — installs the Azure CLI (`az`) + the
  azure-devops extension (the `ado` tool's backend), mirrors the extension into
  OMP's native dir, and (when interactive) prompts for the org/project/PAT,
  persists them to the User env, and runs `az devops login` (PAT mode).
  Flags: -Yes (non-interactive), -Configure (force prompt), -NoConfig, -NoUpdate (no-op).
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$Configure, [switch]$NoConfig, [switch]$NoUpdate)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }

# --- Azure CLI (az) + azure-devops extension --------------------------------
if (Have az) {
  Say "Azure CLI present"
} else {
  Say "Installing Azure CLI"
  if (Have winget) { Run "winget install --id Microsoft.AzureCLI -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "install the Azure CLI from https://aka.ms/installazurecliwindows, then re-run" }
}
if (Have az) {
  az extension show --name azure-devops *> $null
  if ($LASTEXITCODE -eq 0) { Say "azure-devops CLI extension present" }
  else { Say "Adding the azure-devops CLI extension"; Run "az extension add --name azure-devops --only-show-errors" }
}
if (-not (Have git)) { Warn "git not found — pr_checkout / pr_push need it" }

function Az-Login ($orgName, $proj, $pat) {
  if (-not (Have az)) { return }
  $orgUrl = "https://dev.azure.com/$orgName"
  az devops configure --defaults "organization=$orgUrl" $(if ($proj) { "project=$proj" }) --only-show-errors *> $null
  if ($pat) {
    $pat | az devops login --organization $orgUrl --only-show-errors *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "  az devops login OK ($orgUrl)" } else { Warn "az devops login failed — the PAT env still works for the ado tool" }
  }
}

# --- Configure org / project / PAT ------------------------------------------
$interactive = (-not $Yes) -and (-not [Console]::IsInputRedirected)
if ($env:AZURE_DEVOPS_ORG -and $env:AZURE_DEVOPS_PROJECT -and $env:AZURE_DEVOPS_PAT) {
  Say "Azure DevOps already configured via environment — running az devops login"
  $azOrg = ($env:AZURE_DEVOPS_ORG -replace '^https://dev\.azure\.com/', '').TrimEnd('/')
  Az-Login $azOrg $env:AZURE_DEVOPS_PROJECT $env:AZURE_DEVOPS_PAT
} elseif ($NoConfig -or (-not $Configure -and -not $interactive)) {
  Say "Skipping ADO credential prompt (non-interactive)"
  Write-Host "    Set later (User env): AZURE_DEVOPS_ORG (org name) / AZURE_DEVOPS_PROJECT / AZURE_DEVOPS_PAT,  then: az devops login"
} else {
  Say "Configure Azure DevOps credentials (prompting for any not already set)"
  $org = $env:AZURE_DEVOPS_ORG
  if (-not $org) { $org = Read-Host "    AZURE_DEVOPS_ORG (org NAME only, e.g. contoso — not the URL)" }
  if ($org) {
    $org  = ($org -replace '^https://dev\.azure\.com/', '').TrimEnd('/')
    $proj = $env:AZURE_DEVOPS_PROJECT
    if (-not $proj) { $proj = Read-Host "    AZURE_DEVOPS_PROJECT (optional)" }
    if ($env:AZURE_DEVOPS_PAT) {
      $plain = $env:AZURE_DEVOPS_PAT
    } else {
      $pat   = Read-Host "    AZURE_DEVOPS_PAT (Code R/W, PR R/W, Build R, Policy R)" -AsSecureString
      $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat))
    }
    [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_ORG', $org, 'User')
    if ($proj) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PROJECT', $proj, 'User') }
    if ($plain) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', $plain, 'User'); Write-Host "  PAT stored in User environment." }
    Az-Login $org $proj $plain
  } else { Warn "no org entered — skipping ADO credential write" }
}

# --- Load the `ado` tool ----------------------------------------------------
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\azure-devops-fs"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "ado tool loaded into $dest"
}

Say "azure-devops-fs ready. Restart omp; the 'ado' tool is backed by 'az' (e.g. ado op=pr_view uri=adopr://myrepo/4213). ADO PRs use adopr:// URIs, not pr://."
