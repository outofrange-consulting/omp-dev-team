#requires -Version 5.1
<#
  local-llm installer (Windows) — set up local LLMs for OMP, sized to your GPU.
  Detects VRAM/RAM, asks (>=8GB VRAM recommended), installs the backend (Ollama
  auto, or llama.cpp guided), pulls the best-fit models, and wires roles.
  Flags: -Backend ollama|llama.cpp, -Vram N, -Ram N, -All, -ApplyConfig, -DryRun, -Yes
#>
[CmdletBinding()]
param([ValidateSet("ollama","llama.cpp")][string]$Backend, [int]$Vram, [int]$Ram, [switch]$All, [switch]$ApplyConfig, [switch]$DryRun, [switch]$Yes)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { if ($DryRun) { Write-Host "  [dry-run] $cmd" } else { Invoke-Expression $cmd } }
function Ask ($q, $def = 'Y') {
  if ($Yes) { return $true }
  if ([Console]::IsInputRedirected) { return ($def -eq 'Y') }
  $ans = Read-Host "$q $(if ($def -eq 'Y') {'[Y/n]'} else {'[y/N]'})"
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $def }
  return ($ans -match '^(y|Y)')
}

$Bun = if (Have bun) { "bun" } else { Join-Path $HOME ".bun\bin\bun.exe" }
if (-not (Test-Path $Bun) -and -not (Have bun)) { Warn "bun not found — install OMP first (install.ps1 at repo root)"; exit 1 }

if ($Vram) { $env:OMP_LOCAL_VRAM_GB = "$Vram" }
if ($Ram)  { $env:OMP_LOCAL_RAM_GB  = "$Ram" }
$be = if ($Backend) { $Backend } else { "ollama" }

Say "Detecting hardware and computing the model plan"
$plan = & $Bun "$Here\extensions\local-llm.ts" --json --backend $be | ConvertFrom-Json
$vramGB = [int]$plan.hardware.vramGB
$ramGB  = [int]$plan.hardware.ramGB
Write-Host "  Detected: ${vramGB}GB VRAM / ${ramGB}GB RAM (via $($plan.hardware.source))"

if ($vramGB -lt 8) {
  Warn "Only ${vramGB}GB VRAM. Local LLMs want >=8GB; cloud (copilot-preset) is a better fit."
  # Hardware gate: never auto-proceed without a GPU (don't install a backend just
  # because -Yes was passed / input is redirected).
  if ($Yes -or [Console]::IsInputRedirected) { Write-Host "Non-interactive with <8GB VRAM — skipping local-llm setup."; return }
  if (-not (Ask "Set up local LLMs anyway?" 'N')) { Write-Host "Skipping."; return }
} else {
  if (-not (Ask "Set up local LLMs for OMP (sized to ${vramGB}GB VRAM)?" 'Y')) { Write-Host "Skipping."; return }
}

if (-not $Backend) { $be = if (Ask "Use Ollama? (recommended; 'n' = llama.cpp)" 'Y') { "ollama" } else { "llama.cpp" } }
$plan = & $Bun "$Here\extensions\local-llm.ts" --json --backend $be | ConvertFrom-Json
$rolesYaml = $plan.rolesYaml
$roleIds = $plan.roles.PSObject.Properties.Value | Select-Object -Unique
$pulls = if ($All) { $plan.pulls.pull | Select-Object -Unique }
         else { ($plan.pulls | Where-Object { $roleIds -contains $_.id }).pull | Select-Object -Unique }

if ($be -eq "ollama") {
  if (Have ollama) { Say "Ollama present" }
  else {
    Say "Installing Ollama"
    if (Have winget) { Run "winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements" }
    else { $exe = Join-Path $env:TEMP 'OllamaSetup.exe'; Run "Invoke-WebRequest -Uri 'https://ollama.com/download/OllamaSetup.exe' -OutFile '$exe'"; Run "Start-Process -FilePath '$exe' -ArgumentList '/silent' -Wait" }
  }
  Say "Pulling role models (ollama)"
  foreach ($tag in $pulls) { if ($tag) { Run "ollama pull $tag" } }
} else {
  if (Have llama-server) { Say "llama.cpp present" }
  else {
    Say "Installing llama.cpp"
    if (Have winget) { Run "winget install --id ggml.llamacpp -e --accept-source-agreements --accept-package-agreements" }
    else { Warn "Install llama.cpp from https://github.com/ggml-org/llama.cpp/releases and put llama-server on PATH." }
  }
  $top = if ($plan.roles.task) { $plan.roles.task } else { $plan.roles.default }
  Write-Host "`n  llama.cpp is single-model-per-server. Start your primary ($top), e.g.:"
  Write-Host "    llama-server -hf <HF-GGUF-repo-for-$top> -ngl 99 -c 32768 --port 8080"
  if (-not $DryRun) { [Environment]::SetEnvironmentVariable('OMP_LOCAL_BACKEND', 'llama.cpp', 'User') }
}

$cfg = Join-Path $HOME ".omp\agent\config.yml"
if ($ApplyConfig -or (Ask "Append the role wiring to $cfg?" 'Y')) {
  if ($DryRun) { Write-Host "  [dry-run] append modelRoles/enabledModels to $cfg" }
  else {
    New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
    if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'local-llm \(appended' -Quiet)) { Write-Host "  (already present — skipping)" }
    else { "`n# --- local-llm (appended) ---`n$rolesYaml" | Add-Content -Path $cfg; Write-Host "  appended to $cfg" }
  }
}

Write-Host @"

==> local-llm ready (backend: $be).
    - The extension auto-registers fitting local models each session ('local-llm'
      provider); run /local-llm to re-detect and reprint the plan.
    - Planning stays on cloud (plan/default = Opus); execution/cheap roles local.
"@ -ForegroundColor Green
