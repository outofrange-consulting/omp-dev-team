# omp-dev-team — une marketplace Oh-My-Pi

> 🌐 [English](README.md) · **Français**

Quatre plugins **indépendants** pour [Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi).
Installez-en autant que vous voulez — ils ne partagent rien. Un installeur global
met en place OMP et vous guide à travers chacun d'eux.

| Plugin | Rôle |
|---|---|
| **[`dev-team`](plugins/dev-team/)** | **Équipe de dev agentique** — un orchestrateur + 32 agents spécialistes/critiques, le workflow `/specs` → `/plan` → `/build` → `/pr`, **TDD strict** et points de contrôle humains, ~78 skills, et des extensions « garde-fou » bloquantes. Portage de [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (Bryan Finster). Tiers 100 % cloud ; gardez le tier « small » à haut volume bon marché. |
| **[`copilot-preset`](plugins/copilot-preset/)** | **Préréglage modèles GitHub Copilot** — route OMP (et les tiers de dev-team) via `github-copilot` pour tourner sur une licence Copilot. Config seulement : mapping tier→modèle, comparatif tarifaire (crédits IA post-juin 2026), et MAI-Code-1-Flash câblé. |
| **[`token-diet`](plugins/token-diet/)** | **Réduction agressive des tokens** — RTK (sortie shell compressée), CodeGraph (requêtes de graphe de symboles via MCP au lieu de grep+read), et un skill « caveman » de sortie laconique — par-dessus la compaction/`astGrep` natives d'OMP. |
| **[`azure-devops-fs`](plugins/azure-devops-fs/)** | **Azure DevOps comme un système de fichiers** — lecture repos/fichiers/PR/diffs via URIs `ado://` (paginé), **gates/policies** de PR + CI (builds/logs/run), création/checkout/push/complete de PR, commentaires/votes. Authentifié par PAT, cache SQLite. |
| **[`local-llm`](plugins/local-llm/)** | **Modèles locaux dimensionnés à votre matériel** — détecte VRAM/RAM, choisit les meilleurs GGUF par rôle, installe Ollama (ou llama.cpp), les télécharge, et enregistre le fournisseur `local-llm`. Hybride : planification cloud, exécution/rôles bon marché en local. |

## Démarrage rapide (recommandé)

L'installeur global installe OMP, enregistre cette marketplace, propose chaque
plugin + sa config de façon interactive, et corrige votre PATH à la fin.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team
bash install.sh                 # Linux/macOS   (-y non-interactif, --dry-run pour prévisualiser)
#   pwsh -File install.ps1      # Windows
```

**Politique « déjà installé » :** tout est idempotent et **saute** ce qui est déjà
présent (jamais d'écrasement, jamais de nouvelle question) — passez **`--update`**
(`-Update` sous Windows) pour rafraîchir vers la dernière version. Seule exception :
**bun**, mis à niveau automatiquement s'il est sous la version exigée par OMP. Les
fichiers de config ne sont ajoutés qu'une fois (les relances détectent le marqueur).

**Proxys d'entreprise (Zscaler / Trend Micro sous WSL) :** si un proxy qui
intercepte le TLS casse la vérification des certificats, lancez les installeurs
UNIX avec **`--insecure-tls`** (ou exportez `OMP_INSECURE_TLS=1`) pour désactiver la
vérification le temps du run — ça couvre curl/wget (y compris les installeurs
pi-pés), git, node/bun/npm et rustup, et l'installeur global le propage aux
installeurs de plugins. (Les téléchargements de *modèles* Ollama utilisent le
magasin de certificats de Go — si ça échoue encore, importez la CA racine de votre
entreprise dans le magasin système, ou définissez `SSL_CERT_FILE`.) Préférez
importer la CA d'entreprise quand c'est possible ; ce flag est l'échappatoire pour
se débloquer.

## Installation manuelle

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team   # ou :  add ./
omp plugin install dev-team@omp-dev-team
omp plugin install copilot-preset@omp-dev-team
omp plugin install token-diet@omp-dev-team
omp plugin install azure-devops-fs@omp-dev-team
omp plugin install local-llm@omp-dev-team
```

Chaque plugin fournit son propre `install.sh` + `install.ps1` (installe les outils
du plugin dans leur dernière version) — voir son README :

- **dev-team** → `bash plugins/dev-team/install.sh --apply-config` (vérif prérequis + config). 100 % cloud ; pas de backend local.
- **copilot-preset** → `bash plugins/copilot-preset/install.sh --apply-config`, puis `omp` → `/login` → GitHub Copilot.
- **token-diet** → `bash plugins/token-diet/install.sh` (installe RTK + CodeGraph, indexe tous les repos sous votre racine de sources), puis activez le serveur MCP `codegraph`.
- **azure-devops-fs** → `bash plugins/azure-devops-fs/install.sh` (assure Node, demande org/projet/**PAT**), puis activez le serveur MCP `azure-devops`.
- **local-llm** → `bash plugins/local-llm/install.sh` (détecte VRAM/RAM, demande, installe Ollama/llama.cpp, télécharge les meilleurs modèles, câble les rôles).

## Disposition

```
install.sh · install.ps1               # installeur global (OMP + marketplace + invites par plugin)
.claude-plugin/marketplace.json        # catalogue (pluginRoot ./plugins)
plugins/
  dev-team/         agents/ skills/ commands/ rules/ extensions/ .mcp.json
                    config.snippet.yml · install.sh · install.ps1
  copilot-preset/   config.snippet.yml · pricing.md · skills/ · install.{sh,ps1}
  token-diet/       .mcp.json · rules/ · skills/ · install.{sh,ps1}
  azure-devops-fs/  extensions/ commands/ skills/ rules/ knowledge/ .mcp.json · install.{sh,ps1}
  local-llm/        extensions/ (catalog/selector/detect/emit) · skills/ · install.{sh,ps1}
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

Vérifié de bout en bout sous Linux et en intégration continue (Linux/macOS/Windows,
voir `.github/workflows/installers.yml`) : tous les `install.sh` passent `bash -n` +
dry-run ; tous les `install.ps1` se parsent sous PowerShell 7 ; tous les manifestes
sont du JSON valide ; les 8 extensions de dev-team compilent sous `bun` ; RTK,
CodeGraph et OMP s'installent via les commandes exactes des scripts ; et les quatre
plugins s'installent via le vrai OMP.

## Crédits

- `dev-team` porte [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team) (MIT, Bryan Finster).
- `token-diet` regroupe [rtk-ai/rtk](https://github.com/rtk-ai/rtk), [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) et [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman).
- `azure-devops-fs` reprend l'idée « GitHub comme système de fichiers » de [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
