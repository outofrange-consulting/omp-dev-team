# omp-dev-team — une marketplace Oh-My-Pi

> 🌐 [English](README.md) · **Français**

Six plugins **indépendants** pour [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi).
Installez-en autant que vous voulez — ils ne partagent rien. Un installeur global
met en place OMP et vous guide à travers chacun d'eux.

| Plugin | Rôle |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Équipe de dev agentique** — un orchestrateur + 32 agents spécialistes/critiques, le workflow `/specs` → `/plan` → `/build` → `/pr`, un **plan gate strict** (test-after, tests requis) et points de contrôle humains, ~78 skills, et des extensions « garde-fou » bloquantes. Portage de [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (Bryan Finster). Tiers 100 % cloud ; gardez le tier « small » à haut volume bon marché. |
| **[`copilot-preset`](plugins/copilot-preset/)** | **Préréglage modèles GitHub Copilot** — route OMP (et les tiers de dev-team) via `github-copilot` pour tourner sur une licence Copilot. Config seulement : mapping tier→modèle, comparatif tarifaire (crédits IA post-juin 2026), et MAI-Code-1-Flash câblé. |
| **[`token-diet`](plugins/token-diet/)** | **Réduction agressive des tokens** — ctx-wire (compression transparente de la sortie des commandes + scrub des secrets), codebase-memory-mcp (requêtes de graphe de symboles via MCP au lieu de grep+read ; le LSP csharp-ls est conservé pour les sémantiques C# précises), un cache-meter en lecture seule (statusline coût/cache live + `/cache-health`), un skill « caveman » de sortie laconique, un skill « yagni » de code minimal, et un skill `mcp-as-cli-skill-creator` qui transforme un MCP/OpenAPI/GraphQL en CLI à l'exécution sans schéma — par-dessus la compaction/`astGrep` natives d'OMP. |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps comme un système de fichiers** — lecture repos/fichiers/PR/diffs via URIs `ado://` (paginé), **gates/policies** de PR + CI (builds/logs/run), création/checkout/push/complete de PR, commentaires/votes. Propulsé par l'**Azure CLI** (`az` + extension azure-devops), auth PAT, cache SQLite ; fonctionne derrière les proxys TLS d'entreprise. |
| **[`cliproxy`](plugins/cliproxy/)** | **CLIProxyAPI comme fournisseur de modèles** — pointez-le vers une passerelle [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) (URL + clé API) ; l'installeur liste les modèles et écrit un fournisseur `cliproxy` dans `~/.omp/agent/models.yml` avec découverte à l'exécution, utilisable comme `cliproxy/<id-modèle>`. |
| **[`datadog`](plugins/datadog/)** | **Observabilité Datadog depuis le terminal** — via la CLI Datadog [`pup`](https://github.com/DataDog/pup) (logs, métriques, traces/APM, monitors, incidents, dashboards, SLO, RUM, sécurité/audit, visibilité tests CI, observabilité LLM). Un seul skill large `datadog` pilote pup ; l'installeur configure pup + auth. |

## Démarrage rapide (recommandé)

L'installeur global installe OMP, enregistre cette marketplace, propose chaque
plugin + sa config de façon interactive, et corrige votre PATH à la fin.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team
bash install.sh                 # Linux/macOS   (-y non-interactif)
#   pwsh -File install.ps1      # Windows
```

**Fonctionne d'emblée / défauts :** l'installeur global **réinstalle les plugins
choisis à la dernière version** et met runtimes/OMP/outils **à jour par défaut**
(`--no-update` / `-NoUpdate` pour conserver les outils déjà installés). Il **fusionne**
ensuite les défauts gérés model-roles + skills dans `~/.omp/agent/config.yml` et les
serveurs MCP de l'équipe dans `~/.omp/agent/mcp.json` — **tout ce que vous avez déjà
réglé est préservé** (aucun écrasement). Avec **copilot-preset**, ça câble via GitHub
Copilot : `smol`/`task` → **Haiku**, `default`/`plan` → **Sonnet 4.6** (qui pilote
l'orchestrateur dev-team — une tâche non triviale passe par research → plan →
implement → review), `slow` → **Opus** ; sans lui, les mêmes tiers en ids Anthropic.
ctx-wire + codebase-memory-mcp de token-diet et les skills sont aussi activés. `--no-config`
laisse votre config + mcp.json intacts.

Le seul serveur MCP configuré dans `~/.omp/agent/mcp.json` est **`github`** (activé si
un PAT est fourni / `$GITHUB_TOKEN` est défini). **Context7** et **Atlassian** s'utilisent
en **CLI + skill**, pas en MCP — `ctx7` et `acli` (installés par token-diet).

**Contexte de démarrage allégé (par défaut).** OMP charge le schéma JSON de *chaque*
outil dans le system prompt à *chaque* requête : une install dev-team complète
démarrait donc autour de ~29K tokens de surcharge fixe (dont ~18K de « System
tools »). La config générée réduit ça sans perdre de fonctionnalité :

- **dev-team** désactive l'outil `debug` (DAP) et l'outil `eval` (Python/JS) —
  aucun agent ni commande dev-team ne les utilise (ils passent par `bash` + le
  skill `systematic-debugging`).
- **token-diet** pose `tools.discoveryMode: all` : les schémas des outils non
  essentiels sont masqués derrière l'outil de découverte à la demande d'OMP, et
  seul le chemin chaud reste chargé (`read, bash, edit, write, find, search,
  task, todo`). Les outils masqués restent à un appel de découverte près.

Au total le contexte de démarrage tombe à **~20K (-31%)**. Ajustez l'ensemble
toujours-chargé via `tools.essentialOverride`, ou revenez en arrière avec
`--no-config` / en éditant `~/.omp/agent/config.yml`.

**Proxys d'entreprise (Zscaler / Trend Micro sous WSL) :** si un proxy qui
intercepte le TLS casse la vérification des certificats, les installeurs UNIX
offrent deux options :

- **Préféré — faire confiance à la CA d'entreprise :** `--ca-file=/chemin/corp-root-ca.pem`
  (ou `OMP_CA_FILE=…`). La vérification reste **active** ; node/bun, git, curl/wget,
  Python et les **outils Go (pulls de modèles Ollama)** sont pointés vers votre CA via
  `NODE_EXTRA_CA_CERTS`/`SSL_CERT_FILE`/`CURL_CA_BUNDLE`/`GIT_SSL_CAINFO`, et c'est
  **persisté dans votre profil shell** pour qu'`omp` et `ollama pull` en bénéficient ensuite.
  Sous **WSL, pas besoin du .pem** — `--ca-from-windows` exporte automatiquement le
  magasin de certificats Windows (avec les racines d'entreprise), et l'installeur
  global le **propose dès qu'il détecte WSL**. Pour plutôt installer la CA dans le
  magasin **système** de WSL (curl/git/node lui font confiance nativement, sans
  variables d'env), lancez [`scripts/wsl-trust-zscaler.ps1`](scripts/wsl-trust-zscaler.ps1)
  depuis **PowerShell Windows** — il utilise `wsl --user root` (sans sudo) et
  `update-ca-certificates`.
- **Échappatoire — bypass :** `--insecure-tls` (ou `OMP_INSECURE_TLS=1`) désactive la
  vérification le temps du run (curl/wget incl. installeurs pi-pés, git, node/bun/npm).
  Ne peut pas bypasser les outils Go/libcurl (Ollama, etc.) — utilisez `--ca-file` pour ceux-là.

L'installeur global propage le choix aux installeurs de plugins. Lancez les
installeurs **sans `sudo`** (tout est par-utilisateur : `~/.bun`, `~/.local/bin`, `~/.omp`).

## Installation manuelle

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team   # ou :  add ./
omp plugin install dev-team@omp-dev-team
omp plugin install copilot-preset@omp-dev-team
omp plugin install token-diet@omp-dev-team
omp plugin install azure-devops-fs@omp-dev-team
omp plugin install cliproxy@omp-dev-team
omp plugin install datadog@omp-dev-team
```

> **Important — modules d'extension.** OMP ne charge **pas** les modules
> d'extension (le champ `omp.extensions` du `package.json` d'un plugin) depuis une
> installation via le cache marketplace — seuls skills/commands/agents/rules/MCP
> y sont exposés. Les plugins dont le cœur *est* une extension —
> **azure-devops-fs** (l'outil `ado`), **dev-team** (les garde-fous bloquants +
> le routage de modèles) et **cliproxy** (le fournisseur) — ont donc besoin que
> leur installeur tourne aussi. Le `install.sh` global et chaque
> `install.sh`/`install.ps1` de plugin recopient ces modules dans le dossier natif
> d'OMP `~/.omp/agent/extensions/<plugin>/` (toujours découvert, survit aux resets
> de config), pour que l'outil `ado` / les garde-fous / le fournisseur se chargent
> réellement. Un simple `omp plugin install <nom>@omp-dev-team` affichera le skill
> mais **n'enregistrera pas** l'outil.

Chaque plugin fournit son propre `install.sh` + `install.ps1` (installe les outils
du plugin dans leur dernière version) — voir son README :

- **dev-team** → `bash plugins/dev-team/install.sh --apply-config` (vérif prérequis + config). 100 % cloud ; pas de backend local.
- **copilot-preset** → `bash plugins/copilot-preset/install.sh --apply-config`, puis `omp` → `/login` → GitHub Copilot.
- **token-diet** → `bash plugins/token-diet/install.sh` (installe ctx-wire + codebase-memory-mcp, indexe tous les repos sous votre racine de sources), puis activez le serveur MCP `codebase-memory-mcp`.
- **azure-devops-fs** → `bash plugins/azure-devops-fs/install.sh` (installe l'Azure CLI + l'extension azure-devops, demande org/projet/**PAT**, lance `az devops login`), puis redémarrez `omp` pour charger l'outil `ado`.
- **cliproxy** → `bash plugins/cliproxy/install.sh --url=http://localhost:8317 --api-key=…` (liste les modèles de la passerelle, écrit le fournisseur `cliproxy` dans `~/.omp/agent/models.yml`), puis redémarrez `omp`.
- **datadog** → `bash plugins/datadog/install.sh` (installe la CLI Datadog `pup` + configure l'auth ; `--with-skills` pour aussi ajouter les skills par domaine de pup).

## Disposition

```
install.sh · install.ps1               # installeur global (OMP + marketplace + invites par plugin)
.claude-plugin/marketplace.json        # catalogue (pluginRoot ./plugins)
plugins/
  dev-team/         agents/ skills/ commands/ rules/ extensions/ .mcp.json
                    config.snippet.yml · install.sh · install.ps1
                    skills/dev-team-knowledge/  (registries, rubriques, model-routing.json)
  copilot-preset/   config.snippet.yml · pricing.md · skills/ · install.{sh,ps1}
  token-diet/       .mcp.json · rules/ · skills/ · install.{sh,ps1}
  azure-devops-fs/  extensions/ (ado.ts + lib/az.ts) commands/ skills/ rules/ knowledge/ · install.{sh,ps1}
  cliproxy/         extensions/ (cliproxy.ts) · skills/ · install.{sh,ps1}
  datadog/          skills/ (umbrella) · install.{sh,ps1}
```

## Agent Package Manager (APM) & définitions dupliquées

Si vous utilisez Agent Package Manager et lancez `apm compile --all`, les mêmes
agents/skills/rules sont écrits dans `.claude`, `.copilot`, `.cursor`, `.agents`, …
à côté de `.omp`. **OMP ne les charge pas plusieurs fois** — il **déduplique par
nom (le premier gagne)** *avant* le chargement, donc les doublons ne coûtent
**aucun token supplémentaire** et ne sont pas enregistrés deux fois :

- **agents / commands / skills** ne sont scannés que depuis `.omp` › `.claude` ›
  `.codex` › `.gemini` (projet avant user) ; les fichiers de skill identiques sont
  en plus dédupliqués par `realpath`. `.copilot` et `.cursor` **ne sont pas**
  scannés pour ceux-ci.
- **rules** : dédup par nom entre fournisseurs `native › agents › cursor ›
  windsurf › cline` ; les rules de même nom masquées sont exclues du jeu actif.

Notes :

- **Ne supprimez pas les autres dossiers.** `apm compile --all` crée `.claude` /
  `.copilot` / `.cursor` exprès pour Claude Code / Copilot / Cursor, qui en ont
  besoin. Les effacer pour « dé-dupliquer » casserait ces outils — et OMP ignore
  déjà les copies en trop.
- OMP utilise silencieusement la copie **la plus prioritaire** et masque les
  autres. Pour être sûr qu'OMP utilise une variante précise, gardez la version
  canonique dans `.omp/` (ou `.claude/`). Pour les skills, vous pouvez aussi
  cibler/exclure via `skills.includeSkills` / `skills.ignoredSkills` dans votre config.

## Testé

Vérifié de bout en bout et en intégration continue (Linux/macOS/Windows,
voir [`.github/workflows/installers.yml`](.github/workflows/installers.yml)) : tous
les `install.sh` passent `bash -n` ; tous les `install.ps1` se parsent sous
PowerShell 7 ; tous les manifestes sont du JSON valide ; les 8 extensions de
dev-team (plus les modules d'extension de token-diet, azure-devops-fs et cliproxy)
compilent sous `bun` ; ctx-wire, codebase-memory-mcp et OMP s'installent via les commandes
exactes des scripts ; et les six plugins s'installent via le vrai OMP sur chaque OS.

## Crédits

- `dev-team` porte [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `token-diet` regroupe [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire), [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp), [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) et [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (yagni).
- `azure-devops-fs` reprend l'idée « GitHub comme système de fichiers » de [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
