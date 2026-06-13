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

Write-Host @"

==> azure-devops-fs ready. Final step:
    Enable the azure-devops MCP server (enabled:true) in your merged .mcp.json.
    The PAT is injected per-request; it is never written to remotes.
"@ -ForegroundColor Green
