#requires -Version 5.1
<#
  token-diet component installer (Copilot CLI, Windows).
  Installs ctx-wire + PATH shims, codebase-memory-mcp (registered into
  ~/.copilot/mcp-config.json), the postToolUse output-compression hook, and the
  caveman/yagni instructions. Flags: -Yes -NoUpdate -NoConfig -SourcesRoot <path>
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$NoUpdate, [switch]$NoConfig, [string]$SourcesRoot)
$ErrorActionPreference = 'Stop'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Lib  = Resolve-Path (Join-Path $Here '..\..\lib')
if ($env:COPILOT_HOME) { $CopilotHome = $env:COPILOT_HOME } else { $CopilotHome = Join-Path $HOME '.copilot' }
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }
$bin = Join-Path $HOME '.local\bin'; New-Item -ItemType Directory -Force -Path $bin | Out-Null

# --- ctx-wire ---------------------------------------------------------------
if ((Have ctx-wire) -and $NoUpdate) { Say "ctx-wire present" }
elseif (Have ctx-wire) { Say "Updating ctx-wire"; Run "ctx-wire update" }
else {
  Say "Installing latest ctx-wire"
  try { Run "irm https://ctx-wire.dev/install.ps1 | iex" } catch { Warn "ctx-wire install failed — see https://ctx-wire.dev" }
}
if (Have ctx-wire) { try { Run "ctx-wire shims install" } catch {} }

# --- codebase-memory-mcp ----------------------------------------------------
$Cbm = 'codebase-memory-mcp'
if ((Have $Cbm) -and $NoUpdate) { Say "$Cbm present" }
else {
  Say "Installing latest $Cbm"
  try { Run "irm https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1 | iex" }
  catch { Warn "$Cbm install failed — see https://github.com/DeusData/codebase-memory-mcp" }
}

# Register in ~/.copilot/mcp-config.json (merge preserves your existing servers).
if (-not $NoConfig -and (Have $Cbm)) {
  $cbmBin = (Get-Command $Cbm).Source
  $mcp = Join-Path $CopilotHome 'mcp-config.json'
  New-Item -ItemType Directory -Force -Path $CopilotHome | Out-Null
  $patch = New-TemporaryFile
  $cbmEsc = $cbmBin -replace '\\','\\'
  @"
{ "mcpServers": { "$Cbm": { "type": "local", "command": "$cbmEsc", "args": [], "tools": ["*"] } } }
"@ | Set-Content -Path $patch -Encoding utf8
  Say "Registering $Cbm in $mcp"
  if (Have node) { try { Run "node `"$($Lib.Path)\merge-json.mjs`" `"$mcp`" `"$($patch.FullName)`"" | Out-Null } catch { Warn "merge failed: $_" } }
  else { Warn "node not found — add $Cbm to $mcp manually" }
  Remove-Item $patch -ErrorAction SilentlyContinue
}

# --- runtime (postToolUse hook + instructions) ------------------------------
$Dest = Join-Path $CopilotHome 'token-diet'
Say "Installing token-diet runtime into $Dest"
if (Test-Path $Dest) { Remove-Item -Recurse -Force $Dest }
New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'hooks\scripts') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Dest 'instructions') | Out-Null
Copy-Item -Force (Join-Path $Here 'hooks\scripts\*.mjs') (Join-Path $Dest 'hooks\scripts')
Copy-Item -Force (Join-Path $Here 'instructions\*.md') (Join-Path $Dest 'instructions')
Ok "postToolUse output-compression hook + caveman/yagni instructions installed"

# --- index repos ------------------------------------------------------------
if (Have $Cbm) {
  if (-not $SourcesRoot) { if (-not $Yes) { $SourcesRoot = Read-Host "Sources ROOT to index [default: $(Get-Location)]" }; if (-not $SourcesRoot) { $SourcesRoot = (Get-Location).Path } }
  try { Run "$Cbm config set auto_index true" | Out-Null } catch {}
  if (Test-Path (Join-Path $SourcesRoot '.git')) {
    Say "  $Cbm: $SourcesRoot"; try { Run "$Cbm cli index_repository '{\""repo_path\"": \""$SourcesRoot\""}'" } catch {}
  } else {
    $repos = Get-ChildItem -Path $SourcesRoot -Recurse -Depth 3 -Directory -Filter '.git' -ErrorAction SilentlyContinue
    if (-not $repos) { Warn "no git repos under $SourcesRoot — indexing it as one project"; try { Run "$Cbm cli index_repository '{\""repo_path\"": \""$SourcesRoot\""}'" } catch {} }
    else { foreach ($r in $repos) { $p = $r.Parent.FullName; Say "  $Cbm: $p"; try { Run "$Cbm cli index_repository '{\""repo_path\"": \""$p\""}'" } catch {} } }
  }
}

Say "token-diet ready. ctx-wire shims active; $Cbm registered. The output-compression hook is armed per-repo by 'dt init'."
