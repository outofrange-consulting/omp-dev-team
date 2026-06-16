#requires -Version 5.1
<#
  azure-devops-fs installer (Windows) — installs the Azure CLI (`az`) + the
  azure-devops extension (the `ado` tool's backend), mirrors the extension into
  OMP's native dir, and (when interactive) prompts for the org/project/PAT,
  persists them to the User env, and runs `az devops login` (PAT mode).
  Flags: -DryRun, -Yes (non-interactive), -Configure (force prompt), -NoConfig.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Yes, [switch]$Configure, [switch]$NoConfig)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }

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
} elseif ($DryRun) { Write-Host "  [dry-run] az extension add --name azure-devops" }
if (-not (Have git)) { Warn "git not found — pr_checkout / pr_push need it" }

function Az-Login ($orgName, $proj, $pat) {
  if (-not (Have az)) { return }
  $orgUrl = "https://dev.azure.com/$orgName"
  if ($DryRun) { Write-Host "  [dry-run] az devops configure --defaults organization=$orgUrl; az devops login"; return }
  az devops configure --defaults "organization=$orgUrl" $(if ($proj) { "project=$proj" }) --only-show-errors *> $null
  if ($pat) {
    $pat | az devops login --organization $orgUrl --only-show-errors *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "  az devops login OK ($orgUrl)" } else { Warn "az devops login failed — the PAT env still works for the ado tool" }
  }
}

# --- Configure org / project / PAT ------------------------------------------
$interactive = (-not $Yes) -and (-not [Console]::IsInputRedirected)
if ($env:AZURE_DEVOPS_ORG -and $env:AZURE_DEVOPS_PAT) {
  Say "Azure DevOps already configured via environment — running az devops login"
  $azOrg = ($env:AZURE_DEVOPS_ORG -replace '^https://dev\.azure\.com/', '').TrimEnd('/')
  Az-Login $azOrg $env:AZURE_DEVOPS_PROJECT $env:AZURE_DEVOPS_PAT
} elseif ($NoConfig -or (-not $Configure -and -not $interactive)) {
  Say "Skipping ADO credential prompt (non-interactive)"
  Write-Host "    Set later (User env): AZURE_DEVOPS_ORG (org name) / AZURE_DEVOPS_PROJECT / AZURE_DEVOPS_PAT,  then: az devops login"
} else {
  Say "Configure Azure DevOps credentials"
  $org  = Read-Host "    AZURE_DEVOPS_ORG (org NAME only, e.g. contoso — not the URL)"
  if ($org) {
    $org  = ($org -replace '^https://dev\.azure\.com/', '').TrimEnd('/')
    $proj = Read-Host "    AZURE_DEVOPS_PROJECT (optional)"
    $pat  = Read-Host "    AZURE_DEVOPS_PAT (Code R/W, PR R/W, Build R, Policy R)" -AsSecureString
    if ($DryRun) { Write-Host "  [dry-run] setx AZURE_DEVOPS_ORG/PROJECT/PAT (User); az devops login" }
    else {
      [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_ORG', $org, 'User')
      if ($proj) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PROJECT', $proj, 'User') }
      $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat))
      if ($plain) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', $plain, 'User'); Write-Host "  PAT stored in User environment." }
      Az-Login $org $proj $plain
    }
  } else { Warn "no org entered — skipping ADO credential write" }
}

# --- Load the `ado` tool ----------------------------------------------------
# OMP does NOT load extension modules (package.json omp.extensions) from
# marketplace cache installs, so the `ado` tool would otherwise never appear.
# Mirror it into OMP's native user-extension dir, which is always discovered.
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\azure-devops-fs"
  if ($DryRun) { Write-Host "  [dry-run] mirror ado extension -> $dest (OMP native ext dir)" }
  else {
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
    $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
    Say "ado tool loaded into $dest"
  }
}

Write-Host @"

==> azure-devops-fs ready. The `ado` tool is loaded by OMP and backed by `az`.
    Restart omp, then use it, e.g.:
      ado op=pr_view  uri=adopr://myrepo/4213
      ado op=pr_checks repo=myrepo id=4213
    Note: Azure DevOps PRs are NOT pr:// (that's GitHub). Use the `ado` tool with
    adopr:// URIs or repo/id fields.
"@ -ForegroundColor Green
