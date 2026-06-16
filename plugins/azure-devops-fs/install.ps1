#requires -Version 5.1
<#
  azure-devops-fs installer (Windows) — ensures Node.js (for `npx
  @azure-devops/mcp`), pre-warms the LATEST MCP package, and (when interactive)
  prompts for the Azure DevOps org/project/PAT and persists them to the User env.
  Flags: -DryRun, -Yes (non-interactive), -Configure (force prompt), -NoConfig.
#>
[CmdletBinding()]
param([switch]$DryRun, [switch]$Yes, [switch]$Configure, [switch]$NoConfig)
$ErrorActionPreference = 'Stop'

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }

# --- Node.js (provides npx) -------------------------------------------------
$needNode = 20
$haveNode = $false
if (Have node) {
  try { $maj = [int]((node -p 'process.versions.node.split(".")[0]')); $haveNode = ($maj -ge $needNode) } catch {}
}
if ($haveNode) {
  Say "Node.js present ($(node --version))"
} else {
  Say "Installing latest LTS Node.js"
  if (Have winget) { Run "winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "install Node.js >= $needNode from https://nodejs.org" }
}

# --- Pre-warm the Azure DevOps MCP server (latest) --------------------------
if ((Have npx) -or $DryRun) {
  Say "Caching latest @azure-devops/mcp"
  Run "npx -y @azure-devops/mcp@latest --help *> `$null"
}

# --- Configure org / project / PAT ------------------------------------------
$interactive = (-not $Yes) -and (-not [Console]::IsInputRedirected)
if ($env:AZURE_DEVOPS_ORG -and $env:AZURE_DEVOPS_PAT) {
  Say "Azure DevOps already configured via environment — skipping prompt"
} elseif ($NoConfig -or (-not $Configure -and -not $interactive)) {
  Say "Skipping ADO credential prompt (non-interactive)"
  Write-Host "    Set later (User env): AZURE_DEVOPS_ORG / AZURE_DEVOPS_PROJECT / AZURE_DEVOPS_PAT"
} else {
  Say "Configure Azure DevOps credentials"
  $org  = Read-Host "    AZURE_DEVOPS_ORG (e.g. https://dev.azure.com/<org>)"
  if ($org) {
    $proj = Read-Host "    AZURE_DEVOPS_PROJECT (optional)"
    $pat  = Read-Host "    AZURE_DEVOPS_PAT (Code R/W, PR R/W, +Build R)" -AsSecureString
    if ($DryRun) { Write-Host "  [dry-run] setx AZURE_DEVOPS_ORG/PROJECT/PAT (User)" }
    else {
      [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_ORG', $org, 'User')
      if ($proj) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PROJECT', $proj, 'User') }
      $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pat))
      if ($plain) { [Environment]::SetEnvironmentVariable('AZURE_DEVOPS_PAT', $plain, 'User'); Write-Host "  PAT stored in User environment." }
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

==> azure-devops-fs ready. The `ado` tool is now loaded by OMP.
    Set AZURE_DEVOPS_ORG / AZURE_DEVOPS_PAT and use it, e.g.:
      ado op=pr_view  uri=adopr://myrepo/4213
      ado op=pr_checks repo=myrepo id=4213
    Note: Azure DevOps PRs are NOT pr:// (that's GitHub). Use the `ado` tool with
    adopr:// URIs or repo/id fields.
    Optional: the Microsoft azure-devops MCP server (enabled:false) is an
    alternative backend; the PAT is injected per-request, never written to remotes.
"@ -ForegroundColor Green
