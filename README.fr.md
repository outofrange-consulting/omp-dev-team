# omp-dev-team — une marketplace Oh-My-Pi

> 🌐 [English](README.md) · **Français**

Six plugins **indépendants** pour [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi).
Installez-en autant que vous voulez — ils ne partagent rien. Un installeur global
met en place OMP et vous guide à travers chacun d'eux.

| Plugin | Rôle |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Équipe de dev agentique** — portage *verbatim* de [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) v10.20.0 (Bryan Finster) : orchestrateur + 45 agents spécialistes/critiques, 93 skills dont **`/ship`** (spec → plan → build → review → PR en une commande idempotente), un corpus de 58 fichiers knowledge, et les 38 invocations de hooks Python de l'amont exécutées **sans modification**. 456 des 567 fichiers amont arrivent byte-identical ; le reste ne porte que la conversion de format Claude Code → OMP, appliquée par [`scripts/port-upstream-dev-team.mjs`](scripts/port-upstream-dev-team.mjs) — la prochaine montée de version amont tient en une commande. Ouvert sur les modèles : les agents passent par les rôles OMP (`@smol`/`@plan`/`@slow`), jamais par un id de fournisseur. **Requiert `python3`.** |
| **[`copilot-preset`](plugins/copilot-preset/)** | **Préréglage modèles GitHub Copilot** — route OMP (et les tiers de dev-team) via `github-copilot` pour tourner sur une licence Copilot. Config seulement : mapping tier→modèle, comparatif tarifaire (crédits IA post-juin 2026), et MAI-Code-1-Flash câblé. |
| **[`token-diet`](plugins/token-diet/)** | **Compression de contexte via [lean-ctx](https://github.com/yvgude/lean-ctx)** (MIT) — `bash`, `read`, `grep`, `find` et `ls` passent par un binaire Rust local qui compresse la sortie des commandes **et** les lectures de fichiers, résultats de recherche et contexte projet, reconnaît 75+ outils, et met en cache par session : une relecture inchangée devient quasi gratuite. Plus le skill `caveman` pour une **sortie** d'agent laconique, le seul axe que rien d'autre ne traite. Remplace le pack de filtres ctx-wire retiré. |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps comme un système de fichiers** — lecture repos/fichiers/PR/diffs via URIs `ado://` (paginé), **gates/policies** de PR + CI (builds/logs/run), création/checkout/push/complete de PR, commentaires/votes. Propulsé par l'**Azure CLI** (`az` + extension azure-devops), auth PAT, cache SQLite ; fonctionne derrière les proxys TLS d'entreprise. |
| **[`openai-compatible`](plugins/openai-compatible/)** | **N'importe quel fournisseur compatible OpenAI** — pointez-le vers un endpoint LiteLLM, Ollama, vLLM ou LocalAI (nom + URL + clé API) ; l'installeur liste les modèles et écrit le fournisseur dans `~/.omp/agent/models.yml` avec découverte à l'exécution, utilisable comme `<nom>/<id-modèle>`. Clé API en chmod 600, jamais dans l'env. |
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
Copilot : `smol`/`task` → **Haiku**, `default`/`plan` → **Sonnet 5** (qui pilote
l'orchestrateur dev-team + le design archi/domaine — une tâche non triviale passe
par research → plan → implement → review), `slow` → **Opus** (verdicts de sécurité
à fort enjeu) ; sans lui, les mêmes tiers en ids Anthropic.
Le routage lean-ctx de token-diet et les skills sont aussi activés. `--no-config`
laisse votre config + mcp.json intacts.

Trois **serveurs MCP officiels distants** sont fusionnés dans `~/.omp/agent/mcp.json`,
tous en `type: http` :

| serveur | endpoint | auth |
|---|---|---|
| `github` | `https://api.githubcopilot.com/mcp/` | PAT (activé dès qu'un PAT est fourni / `$GITHUB_TOKEN` est défini) |
| `atlassian` | `https://mcp.atlassian.com/v1/mcp/authv2` | OAuth 2.1 au premier appel — rien n'est stocké, activé par défaut |
| `context7` | `https://mcp.context7.com/mcp` | en-tête `CONTEXT7_API_KEY` (offre gratuite) ; enregistré désactivé sans clé |

Atlassian et Context7 étaient auparavant livrés ici en enrobages CLI (`acli`, `ctx7`),
au motif que les schémas d'outils d'un serveur MCP entrent dans chaque system prompt.
OMP 17 a rendu cet argument caduc : `tools.xdev` (actif par défaut) monte les outils
MCP en périphériques `xd://` sous un budget documentaire — un serveur coûte un montage,
pas un dump de schémas. Les deux repassent sur leurs endpoints officiels et les
enrobages disparaissent.

**Contexte de démarrage allégé (par défaut).** Le schéma JSON de *chaque* outil activé
est chargé dans le system prompt à *chaque* requête : la config générée retire donc ce
que l'équipe n'appelle jamais.

- **dev-team** désactive l'outil `debug` (DAP) et l'outil `eval` (Python/JS) —
  aucun agent ni commande dev-team ne les utilise (ils passent par `bash` + le
  skill `systematic-debugging`).

> **Correction (OMP 17).** Les versions précédentes de ce README vendaient un
> réglage `tools.discoveryMode: all` + `tools.essentialOverride` comme gain
> principal (« ~29K → ~20K, −31 % »). **Ces réglages ont été supprimés dans OMP
> 17.0.0** et sont désormais effacés de votre config au chargement : le gain
> n'existe plus, et les installeurs ne les écrivent plus. Le remplaçant d'OMP ne
> demande aucune configuration : `tools.xdev` (actif par défaut) monte les outils
> non essentiels et MCP en périphériques `xd://` sous un budget documentaire de
> 48k/10k caractères.

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
omp plugin install openai-compatible@omp-dev-team
omp plugin install datadog@omp-dev-team
```

> **Important — modules d'extension.** OMP ne charge **pas** les modules
> d'extension (le champ `omp.extensions` du `package.json` d'un plugin) depuis une
> installation via le cache marketplace — seuls skills/commands/agents/rules/MCP
> y sont exposés. Les plugins dont le cœur *est* une extension —
> **azure-devops-fs** (l'outil `ado`), **dev-team** (les garde-fous bloquants +
> le routage de modèles), **openai-compatible** (le fournisseur), **token-diet**
> (read-dedup/context-dedup/context-compress/cache-meter + `path-inject`, qui
> place `~/.local/bin` dans le PATH propre à OMP) et **datadog** (`path-inject`,
> même raison — `pup` s'installe dans `~/.local/bin`) — ont donc besoin que
> leur installeur tourne aussi. Le `install.sh` global et chaque
> `install.sh`/`install.ps1` de plugin recopient ces modules dans le dossier natif
> d'OMP `~/.omp/agent/extensions/<plugin>/` (toujours découvert, survit aux resets
> de config), pour que l'outil `ado` / les garde-fous / le fournisseur / le
> correctif PATH se chargent réellement. Un simple `omp plugin install
> <nom>@omp-dev-team` affichera le skill mais **n'enregistrera pas** l'extension.

Chaque plugin fournit son propre `install.sh` + `install.ps1` (installe les outils
du plugin dans leur dernière version) — voir son README :

- **dev-team** → `bash plugins/dev-team/install.sh --apply-config` (vérif prérequis + config). 100 % cloud ; pas de backend modèle local. La navigation C# passe par l'outil `lsp` natif d'OMP, qui détecte `omnisharp` tout seul.
- **copilot-preset** → `bash plugins/copilot-preset/install.sh --apply-config`, puis `omp` → `/login` → GitHub Copilot.
- **token-diet** → `bash plugins/token-diet/install.sh` (installe lean-ctx + son extension OMP).
- **azure-devops-fs** → `bash plugins/azure-devops-fs/install.sh` (installe l'Azure CLI + l'extension azure-devops, demande org/projet/**PAT**, lance `az devops login`), puis redémarrez `omp` pour charger l'outil `ado`.
- **openai-compatible** → `bash plugins/openai-compatible/install.sh --name=litellm --url=http://localhost:4000 --api-key=…` (liste les modèles de l'endpoint, écrit le fournisseur dans `~/.omp/agent/models.yml`), puis redémarrez `omp`.
- **datadog** → `bash plugins/datadog/install.sh` (installe la CLI Datadog `pup` + configure l'auth ; `--with-skills` pour aussi ajouter les skills par domaine de pup).

## Disposition

```
install.sh · install.ps1               # installeur global (OMP + marketplace + invites par plugin)
.claude-plugin/marketplace.json        # catalogue (pluginRoot ./plugins)
plugins/
  dev-team/         agents/ skills/ commands/ rules/ extensions/ .mcp.json
                    config.snippet.yml · install.sh · install.ps1
                    skills/dev-team-knowledge/  (registries, rubriques, tarifs)
  copilot-preset/   config.snippet.yml · pricing.md · skills/ · install.{sh,ps1}
  token-diet/       .mcp.json · rules/ · skills/ · install.{sh,ps1}
  azure-devops-fs/  extensions/ (ado.ts + lib/az.ts) commands/ skills/ rules/ knowledge/ · install.{sh,ps1}
  openai-compatible/  extensions/ (openai-provider.ts) · skills/ · install.{sh,ps1}
  datadog/          extensions/ (path-inject.ts) · skills/ (umbrella) · install.{sh,ps1}
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
PowerShell 7 (plus `shellcheck` sur les scripts shell) ; tous les manifestes sont du
JSON valide ; les 2 extensions de dev-team et celles de tous les autres plugins
compilent sous `bun` **et** passent `tsc --noEmit` contre les types publiés d'OMP ; lean-ctx et OMP s'installent via les commandes
exactes des scripts ; et les six plugins s'installent via le vrai OMP sur chaque OS.

## Crédits

- `dev-team` porte [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `token-diet` câble [yvgude/lean-ctx](https://github.com/yvgude/lean-ctx) (MIT) et son extension `pi-lean-ctx`, et regroupe [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman).
- `azure-devops-fs` reprend l'idée « GitHub comme système de fichiers » de [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
