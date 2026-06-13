#requires -Version 5.1
<#
  azure-devops-fs installer (Windows) — ensures Node.js (for `npx
  @azure-devops/mcp`) and pre-warms the LATEST MCP package. The `ado` tool is a
  TS extension loaded by OMP (no separate install).
  Flags: -DryRun.
#>
[CmdletBinding()]
param([switch]$DryRun)
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

Write-Host @"

==> azure-devops-fs deps ready. Config next-step (env vars):
    setx AZURE_DEVOPS_ORG your-org
    setx AZURE_DEVOPS_PROJECT your-project   # optional
    setx AZURE_DEVOPS_PAT xxxxxxxx           # Code R/W, PR R/W (+ Build R)
    Then set the azure-devops MCP server enabled:true in your merged .mcp.json.
    The root install.ps1 can prompt for these.
"@ -ForegroundColor Green
