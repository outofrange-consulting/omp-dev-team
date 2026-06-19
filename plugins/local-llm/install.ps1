#requires -Version 5.1
<#
  local-llm installer (Windows) — set up local LLMs for OMP, sized to your GPU.
  Detects VRAM/RAM, asks (>=8GB VRAM recommended), installs the backend (Ollama
  auto, or llama.cpp guided), pulls the best-fit models, and wires roles.
  Flags: -Backend ollama|llama.cpp, -Level smol|balanced|max|local-only, -Vram N,
         -Ram N, -All, -ApplyConfig, -NoUpdate (no-op), -Yes
#>
[CmdletBinding()]
param([ValidateSet("ollama","llama.cpp")][string]$Backend, [ValidateSet("smol","balanced","max","local-only")][string]$Level, [int]$Vram, [int]$Ram, [switch]$All, [switch]$ApplyConfig, [switch]$NoUpdate, [switch]$Yes)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }
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

$lvl = if ($Level) { $Level } elseif ($env:OMP_LOCAL_LEVEL) { $env:OMP_LOCAL_LEVEL } else { "smol" }

Say "Detecting hardware and computing the model plan"
$plan = & $Bun "$Here\extensions\local-llm.ts" --json --backend $be --level $lvl | ConvertFrom-Json
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

if (-not $Level -and -not $env:OMP_LOCAL_LEVEL -and -not ([Console]::IsInputRedirected -or $Yes)) {
  Write-Host "  How much should run on LOCAL models?"
  Write-Host "    1) smol      — only cheap/high-volume roles local; task/default cloud (recommended)"
  Write-Host "    2) balanced  — also task/slow local IF a strong model fits"
  Write-Host "    3) max       — also default local IF a top model fits fully on the GPU"
  Write-Host "    4) local-only— everything local (power users)"
  $c = Read-Host "  Choice [1]"
  $lvl = switch ($c) { '2' {'balanced'} '3' {'max'} '4' {'local-only'} default {'smol'} }
}

$plan = & $Bun "$Here\extensions\local-llm.ts" --json --backend $be --level $lvl | ConvertFrom-Json
$rolesYaml = $plan.rolesYaml
$pulls = if ($All) { $plan.pullsAll } else { $plan.pulls }
Write-Host "  Level: $lvl  ·  models to pull: $($pulls -join ' ')"

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
  [Environment]::SetEnvironmentVariable('OMP_LOCAL_BACKEND', 'llama.cpp', 'User')
}

$cfg = Join-Path $HOME ".omp\agent\config.yml"
if ($ApplyConfig -or (Ask "Append the role wiring to $cfg?" 'Y')) {
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'local-llm \(appended' -Quiet)) { Write-Host "  (already present — skipping)" }
  else { "`n# --- local-llm (appended) ---`n$rolesYaml" | Add-Content -Path $cfg; Write-Host "  appended to $cfg" }
}

# --- Load the provider extension --------------------------------------------
# OMP does NOT load extension modules (package.json omp.extensions) from
# marketplace cache installs, so the local-llm provider would otherwise never
# register. Mirror it into OMP's native user-extension dir.
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\local-llm"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "local-llm provider loaded into $dest"
}

Write-Host @"

==> local-llm ready (backend: $be).
    - The extension auto-registers fitting local models each session ('local-llm'
      provider); run /local-llm to re-detect and reprint the plan.
    - Planning stays on cloud (plan/default = Opus); execution/cheap roles local.
"@ -ForegroundColor Green
