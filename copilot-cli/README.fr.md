# omp-dev-team pour le CLI GitHub Copilot

> 🌐 [English](README.md) · **Français**

L'expérience [omp-dev-team](../README.fr.md) — une **dev-team** agentique, un
**token-diet** agressif et l'observabilité **Datadog** — reconstruite autour des
idiomes du [**CLI GitHub Copilot**](https://docs.github.com/copilot/concepts/agents/about-copilot-cli)
au lieu d'Oh-My-Pi. Même forme, native à `copilot`.

Un installeur global ([`install.sh`](install.sh) / [`install.ps1`](install.ps1))
installe le CLI Copilot puis **propose chaque composant à cocher** — installez le
sous-ensemble voulu.

| Composant | Rôle | Surface Copilot CLI |
|---|---|---|
| **dev-team** | Orchestrateur + agents de workflow (`specs → plan → build → review → pr`) ; **tout le roster OMP porté** — les 30 agents specialists/critics + ~50 skills invocables en `.agent.md`, plus le corpus `dev-team-knowledge` complet ; un **plan gate forcé** (édition de source bloquée tant que non scopé/planifié) + review gate, et les gardes path/freeze/spec/destructive ; le CLI `dt`. | **agents custom** (`.agent.md`), un **hook `preToolUse`**, **`copilot-instructions.md`**, un **corpus de connaissances** embarqué |
| **token-diet** | `ctx-wire` (compression transparente de la sortie shell + scrub des secrets), **codebase-memory-mcp** (requêtes symboles/graphe d'appels au lieu de grep+read), un hook `postToolUse` de compression, et la discipline caveman/yagni. | **shims PATH**, **serveur MCP**, un **hook `postToolUse`**, instructions |
| **datadog** | Datadog depuis le terminal via le CLI [`pup`](https://github.com/DataDog/pup) (logs, métriques, traces, monitors, incidents, SLOs, CI/observabilité LLM). | un **agent `datadog`** pilotant `pup` |

## Pourquoi un portage (le mapping)

Le CLI Copilot n'a ni marketplace de plugins, ni slash commands définies par
l'utilisateur, ni extensions in-process. Il a **quatre** surfaces de
personnalisation, et le portage s'appuie exactement dessus :

| omp-dev-team (Oh-My-Pi) | CLI GitHub Copilot |
|---|---|
| Plugins / marketplace | Un **installeur** qui écrit dans `~/.copilot/` + le `.github/` du dépôt |
| Agents (orchestrateur + specialists) | **Agents custom** — `.agent.md` dans `~/.copilot/agents/` |
| Slash commands `/specs /plan /build /pr` | Les mêmes agents, invoqués avec **`/agent <nom>`** |
| Extensions de garde bloquantes (plan-gate, …) | Un **hook `preToolUse`** (`.github/hooks/*.json`) qui refuse/autorise/modifie les appels d'outils |
| `/scope`, `/plan-approve`, `/freeze`, … | Le **CLI `dt`** (le CLI Copilot n'a pas de slash commands custom) |
| Extensions de compression de sortie | Un **hook `postToolUse`** (`modifiedResult`) |
| Rules / manuel opératoire | **`.github/copilot-instructions.md`** |
| codebase-memory-mcp / MCP GitHub | **Serveurs MCP** dans `~/.copilot/mcp-config.json` |
| Tiers de modèles (copilot-preset) | `/model` + le `model:` en frontmatter de chaque agent |

## Démarrage rapide

Prérequis : **Node.js ≥ 22** (exigence du CLI Copilot) et un abonnement
**GitHub Copilot** actif.

```sh
git clone https://github.com/outofrange-consulting/omp-dev-team
cd omp-dev-team/copilot-cli
bash install.sh                 # Linux/macOS   (-y pour non-interactif)
#   pwsh -File install.ps1      # Windows
```

L'installeur :

1. installe/met à jour le **CLI GitHub Copilot** (`npm i -g @github/copilot`, ou
   Homebrew/winget/le script d'installation),
2. demande, pour chaque composant (dev-team / token-diet / datadog), s'il faut
   l'installer,
3. installe les agents de chaque composant choisi dans `~/.copilot/agents`, ses
   scripts de hook dans `~/.copilot/<composant>/`, fusionne les serveurs MCP dans
   `~/.copilot/mcp-config.json` (**vos serveurs existants sont préservés**), et
   installe le CLI `dt`,
4. propose d'**armer les gardes dev-team dans le dépôt courant** (`dt init`).

Ensuite : ouvrez un nouveau shell, lancez `copilot`, `/login` (GitHub Copilot),
choisissez un modèle avec `/model`, et utilisez les agents avec `/agent <nom>`.

## Le flux dev-team

Le CLI Copilot charge les hooks depuis le **projet** (`.github/hooks/`) : les
gardes bloquantes s'arment donc par dépôt. Dans n'importe quel dépôt :

```sh
dt init            # écrit .github/hooks/*.json + .github/copilot-instructions.md
```

Puis le pipeline forcé (le hook `preToolUse` bloque l'édition de source / le
commit tant que chaque gate n'est pas satisfait) :

```sh
dt scope                 # pré-analyse (ou : dt scope --trivial | --complex)
copilot                  # /agent specs   → écrire les critères .feature
                         # /agent plan     → le plan EST l'artefact de revue
dt plan-approve          # validation humaine → débloque l'édition de source
                         # /agent build    → implémenter ; tests requis
                         # /agent review   → critics sur le diff indexé
dt review-approve        # débloque `git commit`
                         # /agent pr        → ouvrir la PR
dt status                # état du gate ; dt reset ré-arme pour la tâche suivante
```

`dt help` liste toutes les commandes (`freeze`/`unfreeze`, `careful on|off`,
`allow-feature-edits`/`protect-features`, …).

### Ce que les gardes imposent (porté 1:1 des extensions OMP)

- **plan-gate** — l'édition de *source* de production est refusée tant que la
  tâche n'est pas scopée et (si non triviale) `dt plan-approve` exécuté. Docs,
  config, specs et tests ne sont jamais gatés.
- **path-guard** — l'écriture vers `.env`, `*.pem`, `*.key`, `*secret*`,
  `id_rsa`, … est refusée (outils fichiers **et** redirections shell /`tee`/
  `sed -i`/`cp`/`mv`).
- **freeze-guard** — `dt freeze '<glob>'` verrouille des chemins contre l'édition.
- **spec-guard** — modifier une spec BDD `.feature` existante est refusé (corriger
  le code, pas le test) ; en écrire une nouvelle est permis.
- **destructive-guard** — en mode `dt careful on`, les commandes destructrices
  (`rm -rf /`, `git push --force`, `drop table`, `mkfs`, …) sont refusées ; une
  liste sûre (`rm -rf node_modules`, …) reste autorisée.
- **review-gate** — `git commit` est refusé tant que le diff indexé n'est pas
  `dt review-approve` (contournement explicite via `--no-verify`).

> **Honnêteté.** Les gardes sont une application *advisory*, hors arbre de
> travail, par dépôt — des rails pour tenir l'agent et l'humain sur le pipeline,
> **pas un bac à sable étanche**. Un agent exécutant du shell arbitraire pourrait
> atteindre le répertoire d'état. Même posture qu'en amont.

## Modèles (tiers)

Modèles Copilot recommandés par rôle (via `/model`, ou en frontmatter `model:`) :
`claude-haiku-4.5` (critics bon marché à fort volume), `claude-sonnet-4.6`
(défaut équilibré — orchestrateur, plan, build, plupart des critics),
`claude-opus-4.8` (profond — sécurité/architecture, étape plan d'une tâche
complexe). Mettez la réflexion coûteuse dans **scope/plan**, pas dans le build.

## token-diet

```sh
bash packs/token-diet/install.sh    # ctx-wire + codebase-memory-mcp + le hook
```

- **ctx-wire** installe des shims PATH (`~/.local/bin`) qui compressent la sortie
  shell et scrubent les secrets de façon transparente — agnostique au CLI.
- **codebase-memory-mcp** est enregistré dans `~/.copilot/mcp-config.json` pour
  interroger symboles/graphe d'appels au lieu de grep + lecture de fichiers
  entiers. Il indexe les dépôts sous la racine de sources choisie.
- Le **hook `postToolUse`** scrube les secrets, réduit les lignes vides et
  tronque tête/queue les très grosses sorties d'outils *non-shell* (armé par dépôt
  via `dt init`). Toute troncature avec perte est signalée.
- Ajoutez `~/.copilot/token-diet/instructions/token-diet.md` au
  `copilot-instructions.md` d'un dépôt pour la discipline caveman (concis) + yagni
  (code minimal). `dt init` le fait automatiquement quand les deux packs sont
  installés.

## datadog

```sh
bash packs/datadog/install.sh       # installe pup + l'agent datadog
```

`/agent datadog` pilote le CLI `pup`. Authentification via `pup auth login`
(OAuth) ou `DD_API_KEY`/`DD_APP_KEY`/`DD_SITE`.

## Arborescence

```
copilot-cli/
  install.sh · install.ps1            # installeur global (CLI Copilot + cases par composant)
  lib/merge-json.mjs                  # fusion JSON non destructive (mcp-config.json)
  packs/
    dev-team/
      agents/*.agent.md               # 85 agents : workflow + tous les specialists/critics OMP + skills
      hooks/scripts/                  # common.mjs + pre-tool-use.mjs (la garde bloquante)
      instructions/copilot-instructions.md
      knowledge/                      # skills/rules/prompts complets + corpus dev-team-knowledge
      dt.mjs                          # le CLI de gate + `dt init`
      install.sh · install.ps1
    token-diet/
      hooks/scripts/post-tool-use.mjs # compression + scrub des secrets
      mcp/codebase-memory-mcp.json    # snippet MCP (fusionné à l'install)
      instructions/token-diet.md
      install.sh · install.ps1
    datadog/
      agents/datadog.agent.md
      install.sh · install.ps1
```

## Proxys d'entreprise (Zscaler / Trend Micro)

L'installeur Unix reprend celui d'OMP : `--ca-file=/chemin/vers/ca-racine.pem`
(la vérification reste active, persistée dans votre profil), `--ca-from-windows`
sous WSL (export automatique du magasin de confiance Windows), ou l'échappatoire
`--insecure-tls`.

## Relation avec la marketplace Oh-My-Pi

Cet arbre est **autonome** et additif — il ne touche pas aux plugins OMP de
[`../plugins`](../plugins). La logique des gardes et le pack de filtres ctx-wire
sont portés depuis / réutilisés par les plugins OMP `dev-team` et `token-diet`,
afin que les deux restent synchronisés.
