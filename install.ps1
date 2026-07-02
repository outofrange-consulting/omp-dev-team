#requires -Version 5.1
<#
  omp-dev-team — global installer (Windows).
  Installs OMP, registers this marketplace, then interactively offers each plugin
  and its config. Updates the user PATH so everything works in new shells.

  Everything is brought UP TO DATE by default (runtimes, OMP, plugins, tooling).
  Your config is MERGED, never clobbered — anything you've set is preserved.

  Flags:
    -Yes          non-interactive: install all plugins + merge default configs
    -NoUpdate     keep tools already installed (don't refresh bun/node/omp)
    -NoRuntimes   skip installing bun/node (assume they're present)
    -NoConfig     don't write/merge ~/.omp/agent config (keep yours as-is)
    -NoCleanup    don't remove obsolete leftovers (codebase-memory-mcp, CodeGraph,
                  RTK, renamed plugins) from earlier versions

  Corporate TLS (Zscaler/Trend) under WSL: install the CA into the WSL store with
  scripts/wsl-trust-zscaler.ps1 (run from this Windows PowerShell), then run the
  Linux installer inside WSL.
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$NoRuntimes, [switch]$NoUpdate, [switch]$NoConfig, [switch]$NoCleanup)
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Market = 'omp-dev-team'
$OnWindows = ($IsWindows -or $env:OS -eq 'Windows_NT')
$Cfg = Join-Path $HOME ".omp\agent\config.yml"

function Bold ($m) { Write-Host "`n$m" -ForegroundColor White }
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($cmd) { Invoke-Expression $cmd }
function Ask ($q, $def = 'Y') {
  if ($Yes) { return $true }
  $hint = if ($def -eq 'Y') { '[Y/n]' } else { '[y/N]' }
  $ans = Read-Host "$q $hint"
  if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $def }
  return ($ans -match '^(y|Y)')
}
function PromptValue ($label, [switch]$Secret) {
  if ($Yes) { return '' }
  if ($Secret) {
    # Hidden input for secrets (PATs/keys) — Read-Host -AsSecureString does not
    # echo, matching the other ps1 secret prompts. Convert back to plain text.
    $sec = Read-Host "    $label" -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }
  return (Read-Host "    $label")
}
# Restrict a file to the current user only (no inherited access) — the Windows
# equivalent of `chmod 600`. Used to lock down ~/.omp/agent/mcp.json after the
# GitHub PAT is written into it.
function Lock-FileToCurrentUser ($path) {
  if (-not (Test-Path $path)) { return }
  try {
    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)   # disable inheritance, drop inherited rules
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
      $me, 'FullControl', 'Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -Path $path -AclObject $acl
  } catch { Warn "could not lock ACL on $path ($_)" }
}
function Ensure-Path ($dir) {
  if (-not (Test-Path $dir)) { return }
  if (";$env:Path;" -like "*;$dir;*") { return }
  $env:Path = "$dir;$env:Path"
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  if (";$u;" -notlike "*;$dir;*") { [Environment]::SetEnvironmentVariable('Path', "$u;$dir", 'User') }
}
# Run a JS file with bun (preferred) or node.
function Js-Run ($scriptPath, $argList) {
  if (Have bun)  { & bun  $scriptPath @argList; return }
  if (Have node) { & node $scriptPath @argList; return }
  throw "no bun/node available"
}

$MinBun = [version]'1.3.14'
function Ensure-Bun {
  if ($OnWindows) { Ok "bun not required on Windows (OMP ships a native .exe)"; return }
  $okv = $false
  if (Have bun) { try { $okv = ([version]((bun --version).Trim()) -ge $MinBun) } catch {} }
  if ($okv -and $NoUpdate) { Ok "bun $(bun --version)" }
  else {
    Say "Installing bun (>= $MinBun)"
    if (Have winget) { Run "winget install --id Oven-sh.Bun -e --accept-source-agreements --accept-package-agreements" }
    else { Run "irm https://bun.sh/install.ps1 | iex" }
  }
  Ensure-Path (Join-Path $HOME ".bun\bin")
}
function Ensure-Node {
  if ((Have node) -and $NoUpdate) { Ok "node $(node --version)"; return }
  Say "Installing Node.js (LTS)"
  if (Have winget) { Run "winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "could not install Node.js automatically — see https://nodejs.org" }
}

Bold "omp-dev-team installer"
Write-Host "Repo: $Root"

# --- 0) Runtimes (bun, node) -----------------------------------------------
if (-not $NoRuntimes) { Say "Ensuring runtimes"; Ensure-Bun; Ensure-Node }
else { Say "Skipping runtime install (-NoRuntimes)" }

# --- 1) OMP ----------------------------------------------------------------
if ((Have omp) -and $NoUpdate) { Ok "omp present ($(omp --version 2>$null))" }
elseif (Have omp) { Say "Updating OMP"; Run "bun add -g @oh-my-pi/pi-coding-agent@latest" }
else { Say "Installing OMP (latest)"; Run "irm https://omp.sh/install.ps1 | iex" }
Ensure-Path (Join-Path $HOME ".local\bin")
if ($OnWindows) {
  Ensure-Path (Join-Path $env:LOCALAPPDATA 'omp')
} else { Ensure-Path (Join-Path $HOME '.bun\bin') }
if (-not (Have omp)) { Warn "omp not on PATH yet — open a new shell after this" }

# --- 2) Register the marketplace -------------------------------------------
if (Have omp) { Say "Registering marketplace ($Market)"; Run "omp plugin marketplace add `"$Root`" 2>`$null"; Run "omp plugin marketplace update $Market" }

# Mirror a plugin's extension modules into OMP's native user-extension dir
# (~/.omp/agent/extensions/<name>/) so its tool/guard/provider actually loads.
function Install-Extensions ($name, $dir) {
  $src = Join-Path $dir 'extensions'
  if (-not (Test-Path $src)) { return }
  $dest = Join-Path $HOME ".omp\agent\extensions\$name"
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Recurse -Force $src (Join-Path $dest 'extensions')
  $pkg = Join-Path $dir 'package.json'
  if (Test-Path $pkg) { Copy-Item -Force $pkg $dest }
  Ok "$name extension loaded"
}

function Plug ($name, $dir) {
  if (Have omp) { Run "omp plugin install --force $name@$Market" }
  Install-Extensions $name $dir
  $ps1 = Join-Path $dir 'install.ps1'
  if (Test-Path $ps1) {
    $a = @()
    if ($NoUpdate) { $a += '-NoUpdate' }
    if ($name -eq 'token-diet') { $a += '-NoConfig' }
    if ($Yes) { $a += '-Yes' }
    Run "& `"$ps1`" $($a -join ' ')"
  }
}

# Remove leftovers from earlier versions that an upgrade/uninstall does NOT clean:
# dead MCP servers merged into ~/.omp/agent/mcp.json, obsolete tool binaries, and
# renamed/removed plugins. Idempotent, existence-guarded; only touches these exact
# obsolete names. Skip with -NoCleanup.
function Cleanup-Obsolete {
  if ($NoCleanup) { return }
  Bold "Cleanup (obsolete leftovers)"
  $removed = $false

  # 1) Unregister obsolete MCP servers (others kept intact).
  $mcp = Join-Path $HOME ".omp\agent\mcp.json"
  if (Test-Path $mcp) {
    try {
      $cfg = Get-Content -Raw -Path $mcp | ConvertFrom-Json
      if ($cfg.mcpServers) {
        $gone = @()
        foreach ($k in @('codebase-memory','codebase-memory-mcp','codegraph','code-graph')) {
          if ($cfg.mcpServers.PSObject.Properties.Name -contains $k) {
            $cfg.mcpServers.PSObject.Properties.Remove($k); $gone += $k
          }
        }
        if ($gone.Count -gt 0) {
          ($cfg | ConvertTo-Json -Depth 20) | Set-Content -Path $mcp -Encoding UTF8
          Ok ("unregistered MCP server(s): " + ($gone -join ', ')); $removed = $true
        }
      }
    } catch { Warn "could not edit $mcp ($_) — remove codebase-memory-mcp/codegraph entries by hand" }
  }

  # 2) Remove obsolete tool binaries (exact names only).
  $binDirs = @((Join-Path $HOME '.local\bin'), (Join-Path $HOME '.cargo\bin'), (Join-Path $HOME '.bun\bin'))
  foreach ($d in $binDirs) {
    foreach ($n in @('codebase-memory-mcp','codegraph','rtk')) {
      foreach ($ext in @('', '.exe', '.cmd')) {
        $p = Join-Path $d ($n + $ext)
        if (Test-Path $p) { Remove-Item -Force -ErrorAction SilentlyContinue $p; Ok "removed $p"; $removed = $true }
      }
    }
  }

  # 3) Remove renamed/removed plugins (folded into openai-compatible).
  foreach ($n in @('cliproxy','local-llm')) {
    $ed = Join-Path $HOME ".omp\agent\extensions\$n"
    if (Test-Path $ed) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ed; Ok "removed stale plugin extensions: $n"; $removed = $true }
    # `omp plugin uninstall <name>` is the verified subcommand (there is no `plugin remove`).
    if (Have omp) { try { Run "omp plugin uninstall $n" } catch {} }
  }

  # 4) Remove obsolete data/install dirs + the old cc-dev-team env file.
  $dirs = @(
    (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp'),
    (Join-Path $env:LOCALAPPDATA 'codegraph'),
    (Join-Path $env:LOCALAPPDATA 'codebase-memory-mcp'),
    (Join-Path $HOME '.codegraph'),
    (Join-Path $HOME '.codebase-memory-mcp')
  )
  foreach ($d in $dirs) { if ($d -and (Test-Path $d)) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $d; Ok "removed $d"; $removed = $true } }
  $ccEnv = Join-Path $HOME '.claude\cc-dev-team.env'
  if (Test-Path $ccEnv) { Remove-Item -Force -ErrorAction SilentlyContinue $ccEnv; Ok "removed ~/.claude/cc-dev-team.env"; $removed = $true }
  $ccSet = Join-Path $HOME '.claude\settings.json'
  if ((Test-Path $ccSet) -and (Select-String -Path $ccSet -Pattern 'cc-dev-team|cde-dotnetcc' -Quiet)) {
    Warn "~/.claude/settings.json references an old Claude Code dev-team install — review/remove those hook entries by hand (left untouched)."
  }

  if (-not $removed) { Ok "nothing obsolete found (already clean)" }
}

# --- config merge helpers (preserve existing user values) -------------------
function Cfg-Has ($key) {
  if (-not (Test-Path $Cfg)) { return $false }
  return [bool]((Get-Content $Cfg) -match "^$([regex]::Escape($key)):")
}
function Cfg-Add ($key, $block) {  # append YAML block only if top-level key absent
  if (Cfg-Has $key) { return }
  Add-Content -Path $Cfg -Value "`n$block"
}

function Write-Config {
  if ($NoConfig) { Say "Keeping your OMP config as-is (-NoConfig)"; return }
  if (-not ($SEL_DEVTEAM -or $SEL_COPILOT -or $SEL_TOKENDIET -or $SEL_OAI_COMPAT)) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $Cfg) | Out-Null
  if (-not (Test-Path $Cfg)) { New-Item -ItemType File -Force -Path $Cfg | Out-Null }
  Bold "OMP config"; Say "Merging defaults into $Cfg (existing values preserved)"
  if (-not ((Get-Content $Cfg -Raw -ErrorAction SilentlyContinue) -match 'omp-dev-team')) {
    Add-Content -Path $Cfg -Value "# omp-dev-team — merged defaults (your existing values are preserved on re-run)."
  }
  if ($SEL_COPILOT) {
    Cfg-Add 'enabledModels' 'enabledModels: [github-copilot/*]'
    Cfg-Add 'modelProviderOrder' 'modelProviderOrder: [github-copilot]'
    Cfg-Add 'modelRoles' @"
# Models via GitHub Copilot. Run omp -> /login -> GitHub Copilot first.
modelRoles:
  smol: github-copilot/claude-haiku-4.5
  task: github-copilot/claude-haiku-4.5
  default: github-copilot/claude-sonnet-5
  plan: github-copilot/claude-sonnet-5
  slow: github-copilot/claude-opus-4.8
"@
  } elseif ($SEL_DEVTEAM) {
    Cfg-Add 'modelRoles' @"
modelRoles:
  smol: claude-haiku-4-5
  task: claude-haiku-4-5
  default: claude-sonnet-5
  plan: claude-sonnet-5
  slow: claude-opus-4-8
"@
  }
  if ($SEL_DEVTEAM -or $SEL_TOKENDIET) {
    Cfg-Add 'skills' @"
skills:
  enabled: true
  enableSkillCommands: true
  enableClaudeUser: false
  enableClaudeProject: false
"@
  }
  if ($SEL_DEVTEAM) {
    Cfg-Add 'debug' "debug:`n  enabled: false"
    Cfg-Add 'eval'  "eval:`n  py: false`n  js: false"
    Cfg-Add 'task'  "task:`n  maxRecursionDepth: 4`n  simple: default"
  }
  if ($SEL_TOKENDIET) {
    Cfg-Add 'tools' "tools:`n  discoveryMode: all`n  essentialOverride: [read, bash, edit, write, find, search, task, todo]"
  }
  Cfg-Add 'commands' "commands:`n  enableClaudeUser: false`n  enableClaudeProject: false"
  Cfg-Add 'disabledProviders' @"
disabledProviders:
  - claude-plugins
  - codex
  - gemini
  - cursor
  - windsurf
  - opencode
  - cline
"@
  Ok "Config merged"
}

# Merge the team MCP servers into ~/.omp/agent/mcp.json (existing servers kept).
# Atlassian is intentionally NOT here — acli is our go-to for Jira/Confluence.
function Write-Mcp {
  if ($NoConfig) { return }
  if (-not ((Have bun) -or (Have node))) { Warn "no bun/node — skipping mcp.json"; return }
  $mcp = Join-Path $HOME ".omp\agent\mcp.json"
  $gh = $env:GITHUB_TOKEN; if (-not $gh) { $gh = $env:GH_TOKEN }; if (-not $gh) { $gh = $env:GITHUB_PERSONAL_ACCESS_TOKEN }
  if (-not $gh) { $gh = PromptValue 'GitHub PAT for the GitHub MCP (optional, blank to skip)' -Secret }
  # Only GitHub is an MCP, enabled only when a token is available. Atlassian -> acli,
  # Context7 -> ctx7 CLI (both CLI+skill, not MCP). No Miro.
  if ($gh) {
    $ghBlock = '"github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/", "headers": { "Authorization": "Bearer ' + $gh + '" }, "enabled": true }'
  } else {
    $ghBlock = '"github": { "type": "http", "url": "https://api.githubcopilot.com/mcp/", "enabled": false }'
  }
  $patch = New-TemporaryFile
  @"
{
  "mcpServers": {
    $ghBlock
  }
}
"@ | Set-Content -Path $patch -Encoding utf8
  New-Item -ItemType Directory -Force -Path (Split-Path $mcp) | Out-Null
  try { Js-Run (Join-Path $Root 'scripts\merge-json.mjs') @($mcp, $patch.FullName) | Out-Null } catch { Warn "mcp.json merge failed: $_" }
  Remove-Item $patch -ErrorAction SilentlyContinue
  # The PAT is now written as a literal into mcp.json. Lock the file to the
  # current user (no inherited access) — the Windows equivalent of the bash
  # side's `chmod 600 mcp.json`.
  if ($gh) { Lock-FileToCurrentUser $mcp }
  Ok "mcp.json merged ($(if ($gh) { 'github enabled' } else { 'github present (add a PAT to enable)' }))"
}

# --- 3) Per-plugin prompts --------------------------------------------------
Cleanup-Obsolete

Bold "Plugins"
$SEL_DEVTEAM = $false; $SEL_COPILOT = $false; $SEL_TOKENDIET = $false; $SEL_OAI_COMPAT = $false

if (Ask "Install dev-team (agentic dev team: /specs -> /plan -> /build -> /pr)?") {
  Plug 'dev-team' (Join-Path $Root 'plugins\dev-team'); $SEL_DEVTEAM = $true
}
if (Ask "Install copilot-preset (route models through GitHub Copilot)?") {
  Plug 'copilot-preset' (Join-Path $Root 'plugins\copilot-preset'); $SEL_COPILOT = $true
}
if (Ask "Install token-diet (ctx-wire + caveman + yagni + acli + LSP)?") {
  Plug 'token-diet' (Join-Path $Root 'plugins\token-diet'); $SEL_TOKENDIET = $true
  Ensure-Path (Join-Path $HOME ".local\bin")
}
if (Ask "Install openai-compatible (register a LiteLLM/Ollama/vLLM endpoint as a model provider)?" 'N') {
  Plug 'openai-compatible' (Join-Path $Root 'plugins\openai-compatible'); $SEL_OAI_COMPAT = $true
}
if (Ask "Install datadog (Pup CLI + Datadog observability skills)?" 'N') {
  Plug 'datadog' (Join-Path $Root 'plugins\datadog')
}
if (Ask "Install azure-devops-fs (Azure DevOps as a filesystem)?" 'N') {
  Plug 'azure-devops-fs' (Join-Path $Root 'plugins\azure-devops-fs')
}

Write-Config
Write-Mcp

# --- 4) Doctor -------------------------------------------------------------
Bold "Doctor"
foreach ($d in @((Join-Path $HOME '.local\bin'), (Join-Path $HOME '.bun\bin'))) { Ensure-Path $d }
if ($OnWindows) { foreach ($d in @((Join-Path $env:LOCALAPPDATA 'omp'))) { Ensure-Path $d } }
$fail = $false
function Check ($t, $req, $vc) {
  if (Have $t) {
    $v = ''; if ($vc) { try { $v = (Invoke-Expression $vc 2>$null | Select-Object -First 1) } catch {} }
    Ok ("{0} {1}-> {2}" -f $t, $(if ($v) { "($v) " } else { '' }), (Get-Command $t).Source)
  } elseif ($req -eq 'required') { Warn "$t MISSING (required)"; $script:fail = $true }
  else { Warn "$t not found (optional)" }
}
Check git  'required'    'git --version'
Check bun  $(if ($OnWindows) { 'optional' } else { 'required' }) 'bun --version'
Check node 'recommended' 'node --version'
Check omp  'required'    'omp --version'
Check uvx  'optional'    'uvx --version'   # dev-team launches Serena (serena-forge) via uvx

Bold "OMP launch check"
if ((Have omp) -and (omp --version 2>$null)) {
  Ok "omp launches: $(omp --version 2>$null | Select-Object -First 1)"
  Write-Host "  plugins installed:"; (omp plugin list 2>$null | Select-String "@$Market") | ForEach-Object { Write-Host "    $_" }
} else { Warn "omp did not launch — ensure $HOME\.bun\bin is on PATH"; $script:fail = $true }

Write-Host ""
if (-not $fail) { Bold "All set" } else { Bold "Finished with warnings — see above" }
Write-Host "Open a NEW shell so PATH changes persist. If OMP is already running, RESTART it — registry PATH updates only apply to processes started AFTER this script ran; an already-running OMP process keeps its old PATH."
if ($fail) { exit 1 }
