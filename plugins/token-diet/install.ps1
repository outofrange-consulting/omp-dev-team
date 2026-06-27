#requires -Version 5.1
<#
  token-diet installer (Windows) — installs the LATEST ctx-wire + codebase-memory-mcp
  and indexes every git repo under a sources root. caveman/yagni ship as OMP skills.
  Also sets up acli (Atlassian CLI), ast-grep, the .NET SDK + csharp-ls LSP, and
  the ctx7 docs CLI. Everything is refreshed to latest by default.
  Flags: -NoUpdate (keep tools already installed), -Yes (non-interactive),
         -SourcesRoot <path> (parent of your repos; default cwd), -Depth N (default 3),
         -NoConfig.
#>
[CmdletBinding()]
param([switch]$NoUpdate, [switch]$Yes, [string]$SourcesRoot, [int]$Depth = 3, [switch]$NoConfig)
$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say  ($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }

$BinDir = Join-Path $HOME ".local\bin"
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

# --- ctx-wire (transparent command-output compression + secret scrubbing) ----
if ((Have ctx-wire) -and $NoUpdate) {
  Say "ctx-wire present"
} elseif (Have ctx-wire) {
  Say "Updating ctx-wire"; Run "ctx-wire update"
} else {
  Say "Installing latest ctx-wire"; Run "irm https://ctx-wire.dev/install.ps1 | iex"
}
if (Have ctx-wire) { Say "Installing ctx-wire PATH shims"; Run "ctx-wire shims install" }

# --- codebase-memory-mcp (MCP) ----------------------------------------------
if ((Have codebase-memory-mcp) -and $NoUpdate) { Say "codebase-memory-mcp present" }
else {
  Say "Installing latest codebase-memory-mcp"
  try {
    $cbmInstaller = Join-Path $env:TEMP 'codebase-memory-mcp-install.ps1'
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1' -OutFile $cbmInstaller
    & $cbmInstaller
  } catch { Warn "codebase-memory-mcp install failed: $_ — see https://github.com/DeusData/codebase-memory-mcp" }
}

# Ensure ~/.local/bin is on PATH (user scope)
if (";$env:Path;" -notlike "*;$BinDir;*") {
  Say "Adding $BinDir to your user PATH"
  $userPath = [Environment]::GetEnvironmentVariable('Path','User')
  [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
  $env:Path = "$env:Path;$BinDir"
}
# Ensure codebase-memory-mcp bin is on PATH (Windows: %LOCALAPPDATA%\Programs\codebase-memory-mcp)
if ($env:OS -eq 'Windows_NT' -or $IsWindows) {
  $cbmBin = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp'
  if ((Test-Path $cbmBin) -and (";$env:Path;" -notlike "*;$cbmBin;*")) {
    Say "Adding codebase-memory-mcp bin to user PATH"
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$cbmBin", 'User')
    $env:Path = "$env:Path;$cbmBin"
  }
}

# --- acli (official Atlassian CLI — our go-to for Atlassian) -----------------
if ((Have acli) -and $NoUpdate) { Say "acli present" }
else {
  Say "Installing Atlassian CLI (acli)"
  try { Invoke-WebRequest -Uri 'https://acli.atlassian.com/windows/latest/acli_windows_amd64/acli.exe' -OutFile (Join-Path $BinDir 'acli.exe') }
  catch { Warn "acli download failed — see https://developer.atlassian.com/cloud/acli/" }
}

# --- ast-grep (structural search/rewrite) -----------------------------------
if ((Have ast-grep) -and $NoUpdate) { Say "ast-grep present" }
elseif (Have winget) { Say "Installing ast-grep (winget)"; Run "winget install --id ast-grep.ast-grep -e --accept-source-agreements --accept-package-agreements" }
elseif (Have npm) { Say "Installing ast-grep (npm)"; Run "npm install -g @ast-grep/cli" }
else { Warn "need npm or winget to install ast-grep — see https://ast-grep.github.io" }

# --- .NET SDK (official MS script) + csharp-ls (C# LSP) ----------------------
if (-not (Have dotnet)) {
  Say "Installing .NET SDK (LTS) via the official Microsoft script"
  try {
    $dis = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $dis
    & $dis -Channel LTS -InstallDir (Join-Path $HOME '.dotnet')
    $env:DOTNET_ROOT = Join-Path $HOME '.dotnet'
    $env:Path = "$($env:DOTNET_ROOT);$($env:DOTNET_ROOT)\tools;$env:Path"
    [Environment]::SetEnvironmentVariable('DOTNET_ROOT', $env:DOTNET_ROOT, 'User')
  } catch { Warn ".NET SDK install failed: $_" }
}
if (Have dotnet) {
  if ((Have csharp-ls) -and $NoUpdate) { Say "csharp-ls present" }
  elseif (Have csharp-ls) { Say "Updating csharp-ls"; Run "dotnet tool update -g csharp-ls" }
  else { Say "Installing csharp-ls (.NET C# language server)"; Run "dotnet tool install -g csharp-ls" }
} else { Warn "dotnet not found — skipping csharp-ls (C# LSP)" }

# --- ctx7 CLI (context7 library documentation) ------------------------------
if (Have npm) {
  if ((Have ctx7) -and $NoUpdate) { Say "ctx7 CLI present" }
  else { Say "Installing ctx7 CLI"; Run "npm install -g ctx7" }
} else { Warn "npm not found — ctx7 unavailable (install Node.js)" }

# --- Scan/index source repos with codebase-memory-mcp -----------------------
if (-not $SourcesRoot) {
  if (-not $Yes -and -not [Console]::IsInputRedirected) {
    $ans = Read-Host "Sources ROOT to scan (every git repo under it is indexed)? [default: $(Get-Location)]"
    if (-not [string]::IsNullOrWhiteSpace($ans)) { $SourcesRoot = $ans }
  }
  if (-not $SourcesRoot) { $SourcesRoot = (Get-Location).Path }
}
function Index-One ($repo) {
  Say "  codebase-memory-mcp: $repo"
  # Build the JSON with ConvertTo-Json so Windows backslash paths are escaped
  # correctly, and pass it as a single argument via the call operator (avoids
  # Invoke-Expression quoting pitfalls).
  $payload = @{ repo_path = $repo } | ConvertTo-Json -Compress
  & codebase-memory-mcp cli index_repository $payload
}
if (Have codebase-memory-mcp) {
  & codebase-memory-mcp config set auto_index true
  if (Test-Path (Join-Path $SourcesRoot '.git')) {
    Say "Scanning single repo: $SourcesRoot"; Index-One $SourcesRoot
  } else {
    Say "Scanning every git repo under: $SourcesRoot (depth $Depth)"
    $repos = Get-ChildItem -Path $SourcesRoot -Recurse -Depth $Depth -Directory -Filter '.git' -ErrorAction SilentlyContinue | ForEach-Object { $_.Parent.FullName }
    if ($repos.Count -gt 0) { foreach ($r in $repos) { Index-One $r }; Say "Indexed $($repos.Count) repo(s) under $SourcesRoot." }
    else { Warn "no git repos under $SourcesRoot — indexing it as a single project"; Index-One $SourcesRoot }
  }
}

# --- Enable the bundled skills (caveman, yagni, codebase-memory, token-diet) -
if (-not $NoConfig) {
  $cfg = Join-Path $HOME ".omp\agent\config.yml"
  New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
  if ((Test-Path $cfg) -and (Select-String -Path $cfg -Pattern 'token-diet skills' -Quiet)) { Say "Skills already enabled in $cfg" }
  else { "`n" + (Get-Content -Raw (Join-Path $Here 'config.snippet.yml')) | Add-Content -Path $cfg; Say "Enabled token-diet skills in $cfg" }
}

# --- Load the context-transform extensions ----------------------------------
$src = Join-Path $Here 'extensions'
if (Test-Path $src) {
  $dest = Join-Path $HOME ".omp\agent\extensions\token-diet"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $Here 'package.json'; if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Say "read-dedup + context-dedup + context-compress (safe) loaded into $dest"
}

Say "token-diet active: ctx-wire shims, codebase-memory-mcp (MCP), ast-grep, .NET/csharp-ls LSP, ctx7, acli, /caveman + /yagni. Restart omp."
