#requires -Version 5.1
<#
  cc-dev-team — global installer (Windows).
  Installs the Claude Code CLI, registers this marketplace, then interactively
  offers each plugin and each external dependency (ctx-wire, codebase-memory-mcp,
  pup). Merges ~/.claude/settings.json structurally (JSON) — never clobbers.

  Flags:
    -Yes        non-interactive: install all plugins + their default deps
    -NoUpdate   keep tools already installed (don't refresh them)
    -NoNode     skip installing Node.js (required by the plugin hooks/statusline)
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$NoUpdate, [switch]$NoNode)
$ErrorActionPreference = 'Stop'

$Root     = Split-Path -Parent $MyInvocation.MyCommand.Path   # the claude-code\ dir
$Market   = 'cc-dev-team'
$Settings = Join-Path $HOME '.claude\settings.json'
$Secrets  = Join-Path $HOME '.claude\cc-dev-team.env'

function Bold ($m) { Write-Host "`n$m" -ForegroundColor White }
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "  ok $m" -ForegroundColor Green }
function Warn ($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Have ($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Run  ($c) { Invoke-Expression $c }
function Ask ($q, $def = 'Y') {
  if ($Yes) { return $true }
  $hint = if ($def -eq 'Y') { '[Y/n]' } else { '[y/N]' }
  $ans = Read-Host "$q $hint"; if ([string]::IsNullOrWhiteSpace($ans)) { $ans = $def }
  return ($ans -match '^(y|Y)')
}
function PromptValue ($label, [switch]$Secret) {
  if ($Yes) { return '' }
  if ($Secret) { $s = Read-Host "    $label" -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)) }
  return (Read-Host "    $label")
}
function Ensure-Path ($dir) {
  if (-not (Test-Path $dir)) { return }
  if (";$env:Path;" -like "*;$dir;*") { return }
  $env:Path = "$dir;$env:Path"
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  if (";$u;" -notlike "*;$dir;*") { [Environment]::SetEnvironmentVariable('Path', "$u;$dir", 'User') }
}
function Merge-Settings ($json) {
  if (-not (Have node)) { Warn "no node — skipping settings merge"; return }
  $patch = New-TemporaryFile; $json | Set-Content -Path $patch -Encoding utf8
  New-Item -ItemType Directory -Force -Path (Split-Path $Settings) | Out-Null
  try { & node (Join-Path $Root 'scripts\merge-json.mjs') $Settings $patch.FullName | Out-Null }
  catch { Warn "settings merge failed: $_" }
  Remove-Item $patch -ErrorAction SilentlyContinue
}
function Plugin-Install ($name) {
  if (Have claude) {
    try { & claude plugin install "$name@$Market" --scope user | Out-Null; Ok "plugin $name installed" }
    catch { Warn "could not auto-install $name (run: claude plugin install $name@$Market)" }
  }
}

function Ensure-Node {
  if ($NoNode) { Warn "skipping Node install (-NoNode)"; return }
  if ((Have node) -and ($NoUpdate -or $true)) { Ok "node $(node --version)"; return }
  Say "Installing Node.js (LTS)"
  if (Have winget) { Run "winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements" }
  else { Warn "install Node.js from https://nodejs.org, then re-run" }
}
function Ensure-Claude {
  if ((Have claude) -and $NoUpdate) { Ok "claude present ($(claude --version 2>$null))"; return }
  if (Have claude) { Say "Updating Claude Code"; try { & claude update | Out-Null } catch {}; Ok "claude $(claude --version 2>$null)"; return }
  Say "Installing Claude Code CLI"
  try { Run "irm https://claude.ai/install.ps1 | iex" }
  catch {
    if (Have winget) { Run "winget install --id Anthropic.ClaudeCode -e --accept-source-agreements --accept-package-agreements" }
    elseif (Have npm) { Run "npm install -g @anthropic-ai/claude-code" }
    else { Warn "Claude Code install failed — see https://docs.claude.com/claude-code" }
  }
  Ensure-Path (Join-Path $HOME '.local\bin')
  if (-not (Have claude)) { Warn "claude not on PATH yet — open a new shell after this" }
}

function Install-CtxWire {
  if ((Have ctx-wire) -and $NoUpdate) { Ok "ctx-wire present" }
  else { Say "Installing ctx-wire"; try { Run "irm https://ctx-wire.dev/install.ps1 | iex" } catch { Warn "ctx-wire install failed — see https://ctx-wire.dev" } }
  if (Have ctx-wire) { try { & ctx-wire shims install | Out-Null; Ok "ctx-wire shims installed" } catch {} }
}
function Install-CodebaseMemory {
  if ((Have codebase-memory-mcp) -and $NoUpdate) { Ok "codebase-memory-mcp present"; return }
  Say "Installing codebase-memory-mcp"
  try { Run "irm https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.ps1 | iex" }
  catch { Warn "codebase-memory-mcp: no Windows auto-install — see https://github.com/DeusData/codebase-memory-mcp" }
  if (Have codebase-memory-mcp) { try { & codebase-memory-mcp config set auto_index true | Out-Null } catch {}; Ok "codebase-memory-mcp ready" }
}
function Install-Pup {
  if ((Have pup) -and $NoUpdate) { Ok "pup present"; return }
  Say "Installing the Datadog pup CLI"
  if (Have winget) { try { Run "winget install --id DataDog.pup -e --accept-source-agreements --accept-package-agreements"; Ok "pup (winget)"; return } catch {} }
  Warn "pup: install from https://github.com/DataDog/pup/releases (no winget package found)"
}
function Datadog-Auth {
  if (-not (Have pup)) { return }
  if (Ask "    Authenticate Datadog now via OAuth (pup auth login)?" 'Y') {
    try { & pup auth login } catch { Warn "pup auth login failed — set DD_API_KEY/DD_APP_KEY/DD_SITE instead" }
  } else {
    $site = PromptValue 'DD_SITE (e.g. datadoghq.com / datadoghq.eu; blank to skip)'
    if ($site) {
      $key = PromptValue 'DD_API_KEY' -Secret; $app = PromptValue 'DD_APP_KEY' -Secret
      [Environment]::SetEnvironmentVariable('DD_SITE', $site, 'User')
      if ($key) { [Environment]::SetEnvironmentVariable('DD_API_KEY', $key, 'User') }
      if ($app) { [Environment]::SetEnvironmentVariable('DD_APP_KEY', $app, 'User') }
      Ok "Datadog keys saved to User environment"
    }
  }
}

function Ensure-Az {
  if (Have az) { Ok "azure-cli present" }
  else { Say "Installing the Azure CLI"; if (Have winget) { Run "winget install --id Microsoft.AzureCLI -e --accept-source-agreements --accept-package-agreements" } else { Warn "install from https://aka.ms/installazurecliwindows" } }
  if (Have az) { try { az extension show --name azure-devops *> $null; if ($LASTEXITCODE -ne 0) { az extension add --name azure-devops --only-show-errors *> $null } } catch {} }
}
function Wire-AnthropicEnv ($base, $token, $sonnet, $opus, $haiku) {
  Merge-Settings ('{ "env": { "ANTHROPIC_BASE_URL": "' + $base + '", "ANTHROPIC_AUTH_TOKEN": "' + $token + '", "ANTHROPIC_DEFAULT_SONNET_MODEL": "' + $sonnet + '", "ANTHROPIC_DEFAULT_OPUS_MODEL": "' + $opus + '", "ANTHROPIC_DEFAULT_HAIKU_MODEL": "' + $haiku + '" } }')
}

Bold "cc-dev-team installer"
Write-Host "Marketplace: $Root"

Ensure-Node
Ensure-Claude

if (Have claude) {
  Say "Registering marketplace ($Market)"
  try { & claude plugin marketplace add "$Root" | Out-Null } catch { try { & claude plugin marketplace update $Market | Out-Null } catch {} }
}

Bold "Plugins & dependencies — check each one"
$SEL_DEV = $false; $SEL_TD = $false; $SEL_DD = $false; $SEL_ADO = $false; $SEL_CLIPROXY = $false; $SEL_COPILOT = $false; $WIRE_STATUSLINE = $false

if (Ask "[dev-team]  Agentic dev team (/specs -> /plan -> /build -> /pr, 30 agents, gates)?") {
  $SEL_DEV = $true; Plugin-Install 'dev-team'
}
if (Ask "[token-diet] Token-reduction toolkit (statusline + skills)?") {
  $SEL_TD = $true; Plugin-Install 'token-diet'
  if (Ask "    +- [ctx-wire]            transparent command-output compression + secret scrub?" 'Y') { Install-CtxWire }
  if (Ask "    +- [codebase-memory-mcp] symbol/call-graph MCP (the token-diet .mcp.json server)?" 'Y') { Install-CodebaseMemory }
  if (Ask "    +- wire the live cache/cost statusline into settings.json?" 'Y') { $WIRE_STATUSLINE = $true }
}
if (Ask "[datadog]   Datadog observability via the pup CLI?") {
  $SEL_DD = $true; Plugin-Install 'datadog'
  if (Ask "    +- [pup] install the Datadog pup CLI now?" 'Y') { Install-Pup; Datadog-Auth }
  if (Ask "    +- also install pup's per-domain skills for Claude Code (pup skills install claude)?" 'N') { if (Have pup) { try { & pup skills install claude } catch { try { & pup skills install } catch {} } } }
}
if (Ask "[azure-devops] Official Azure DevOps MCP (@azure-devops/mcp)?" 'N') {
  $SEL_ADO = $true; Ensure-Az; Plugin-Install 'azure-devops'
  $org = PromptValue 'Azure DevOps org NAME (e.g. contoso — not the URL)'
  if ($org -and (Have az)) {
    try { az devops configure --defaults "organization=https://dev.azure.com/$org" --only-show-errors *> $null } catch {}
    if (Ask "    +- run 'az login' now (browser)?" 'Y') { try { az login --only-show-errors *> $null } catch { Warn "az login failed — run it manually before using ADO" } }
  }
  $orgNote = if ($org) { " — it's '$org'" } else { '' }
  Warn "Set the org on the plugin when Claude Code prompts (userConfig.org)$orgNote. Auth is your az session."
}
if (Ask "[cliproxy]  Route Claude Code through a CLIProxyAPI gateway?" 'N') {
  $SEL_CLIPROXY = $true; Plugin-Install 'cliproxy'
  $url = PromptValue 'CLIProxyAPI base URL [http://127.0.0.1:8317]'; if (-not $url) { $url = 'http://127.0.0.1:8317' }
  $key = PromptValue 'Gateway API key (Bearer; blank if none)' -Secret; if (-not $key) { $key = 'cliproxy' }
  $son = PromptValue 'model id for the SONNET tier (gateway model)'
  Wire-AnthropicEnv $url $key $son $son $son
  Ok "cliproxy: ANTHROPIC_BASE_URL -> $url (edit per-tier models in ~/.claude/settings.json)"
}
if (Ask "[copilot-preset] Run Claude Code on a GitHub Copilot license (copilot-api bridge)?" 'N') {
  $SEL_COPILOT = $true; Plugin-Install 'copilot-preset'
  if ($SEL_CLIPROXY) { Warn "copilot-preset and cliproxy both set ANTHROPIC_BASE_URL — mutually exclusive; the merge keeps the FIRST value. Edit settings.json env to choose." }
  Say "The bridge runs as: npx copilot-api@latest start --claude-code  (port 4141; must stay running)"
  $son = PromptValue 'Copilot model id for SONNET tier [claude-sonnet-4.5]'; if (-not $son) { $son = 'claude-sonnet-4.5' }
  Wire-AnthropicEnv 'http://localhost:4141' 'dummy' $son $son $son
  Ok "copilot-preset: ANTHROPIC_BASE_URL -> http://localhost:4141 — start the bridge before running claude"
}

Bold "Settings"
Say "Merging defaults into $Settings (existing values preserved)"
if ($SEL_DEV -or $SEL_TD -or $SEL_DD) {
  Merge-Settings @'
{
  "permissions": {
    "deny": [
      "Read(./.env)", "Read(./.env.*)", "Read(./**/*.pem)", "Read(./**/*.key)",
      "Read(./**/id_rsa)", "Read(./**/*secret*)", "Read(./**/*credential*)"
    ],
    "ask": [
      "Bash(rm -rf *)", "Bash(git push --force *)", "Bash(git push -f *)",
      "Bash(git reset --hard *)"
    ]
  }
}
'@
}
if ($WIRE_STATUSLINE) {
  $tdDir = (Join-Path $Root 'plugins\token-diet') -replace '\\','/'
  $hasStatus = $false
  if (Test-Path $Settings) { try { $hasStatus = [bool]((Get-Content $Settings -Raw | ConvertFrom-Json).statusLine) } catch {} }
  if ($hasStatus) { Warn "you already have a statusLine — leaving it. cache-meter: node $tdDir/statusline/cache-meter.mjs" }
  else { Merge-Settings ('{ "statusLine": { "type": "command", "command": "node \"' + $tdDir + '/statusline/cache-meter.mjs\"", "padding": 0 } }'); Ok "cache-meter statusline wired" }
}
Ok "Settings merged"

Bold "Doctor"
$fail = $false
function Check ($t, $req, $vc) {
  if (Have $t) { $v=''; if ($vc) { try { $v = (Invoke-Expression $vc 2>$null | Select-Object -First 1) } catch {} }
    Ok ("{0} {1}-> {2}" -f $t, $(if ($v) { "($v) " } else { '' }), (Get-Command $t).Source) }
  elseif ($req -eq 'required') { Warn "$t MISSING (required)"; $script:fail = $true } else { Warn "$t not found (optional)" }
}
Check git    'required'    'git --version'
Check node   'required'    'node --version'
Check claude 'required'    'claude --version'
if ($SEL_TD) { Check ctx-wire 'optional' 'ctx-wire --version'; Check codebase-memory-mcp 'optional' 'codebase-memory-mcp --version' }
if ($SEL_DD) { Check pup 'optional' 'pup version' }

if (Have claude) { Bold "Plugins"; (claude plugin list 2>$null | Select-String "$Market|dev-team|token-diet|datadog") | ForEach-Object { Write-Host "  $_" } }

Write-Host ""
if (-not $fail) { Bold "All set" } else { Bold "Finished with warnings — see above" }
Write-Host "Open a NEW shell so PATH changes persist, then run: claude"
if ($fail) { exit 1 }
