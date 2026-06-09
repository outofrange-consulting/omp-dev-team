# omp-dev-team

Portage pour **[Oh-My-Pi (OMP)](https://github.com/can1357/oh-my-pi)** du harness
**[agentic-dev-team](https://github.com/bdfinst/agentic-dev-team)** de Bryan Finster :
une équipe de développement pilotée par des agents-personas, avec orchestration
trois phases, redirection entre agents, extensions de blocage, usage MCP — et la
possibilité de **rediriger le « petit » palier de modèles vers un modèle local**
qui tourne bien sur une **RTX 5070 Ti 16 Go**.

> L'intention de routage : les modèles locaux remplacent les **petits modèles**
> (agents de revue par motif, à fort volume), **pas** Sonnet/Opus qui restent en
> cloud pour le raisonnement.

---

## Ce que c'est

Un workspace OMP complet sous `.omp/` (installable aussi comme **plugin
marketplace**, voir *Installation*) :

| Brique | Emplacement | Rôle |
|---|---|---|
| **Agents** (32) | `.omp/agents/*.md` | personas + agents de revue, lancés via l'outil `task` |
| **Skills** (78) | `.omp/skills/*/SKILL.md` | savoir-faire chargé à la demande (`/skill:<nom>` ou `read skill://<nom>`) |
| **Commands** | `.omp/commands/*.md` | points d'entrée du pipeline (`/specs` `/plan` `/build` `/pr` …) |
| **Extensions** (8) | `.omp/extensions/*.ts` | les « scripts de blocage » (gardes + routage), en TypeScript natif OMP |
| **Rules** | `.omp/rules/*.md` | garde-fous toujours/scopés (discipline de sortie, TDD, authoring) |
| **Knowledge** | `.omp/skills/dev-team-knowledge/` | corpus de référence (registres, rubriques, OWASP, taxonomies de test), lu via `skill://dev-team-knowledge/<fichier>` — portable (résout depuis n'importe quel projet) |
| **MCP** | `.omp/.mcp.json` (+ `.omp/mcp.json` pour le mode workspace) | serveurs MCP (CodeGraph, GitHub) |
| **Manuel d'équipe** | `.omp/APPEND_SYSTEM.md` | contexte toujours chargé (orchestration, routage, flux) |

### Correspondance Claude Code → OMP

| agentic-dev-team (Claude Code) | → | omp-dev-team (OMP) |
|---|---|---|
| `agents/*.md` (`tools`, `model: haiku/sonnet/opus`) | → | `.omp/agents/*.md` (`tools` minuscules, `spawns`, `model:` concret/role) |
| `skills/*/SKILL.md` | → | `.omp/skills/*/SKILL.md` |
| skills *user-invocable* (slash) | → | `.omp/commands/*.md` + `/skill:<nom>` |
| hooks shell (`destructive-guard`, `tdd-guard`, gate `pre-commit-review`, secrets) | → | extensions TS (`tool_call` bloquant) |
| `agent-model-resolve.sh` + `model-routing.json` (réécriture du modèle au dispatch) | → | `modelRoles` + extension `model-routing` (gate de dispo + log) |
| usage MCP (`mcp__codegraph__*`) | → | `.omp/mcp.json` |
| paliers de modèles | → | **palier petit = local**, Sonnet/Opus = cloud |

---

## Installation

### Option A — Plugin OMP (recommandé : installé une fois, zéro copie)

Le repo embarque un catalogue marketplace (`.claude-plugin/marketplace.json`).
OMP met le contenu en cache **une seule fois** ; tu l'actives **par projet**
(opt-in) via un petit `config.yml`, sans copier `.omp/` nulle part.

**1. Installer l'équipe** (agents, skills, corpus de connaissance, commandes, MCP) :

```sh
# depuis le clone local (le marketplace.json n'est pas encore poussé sur GitHub) :
omp plugin marketplace add ~/sources/omp-dev-team
# après push : omp plugin marketplace add outofrange-consulting/omp-dev-team
omp plugin install dev-team@omp-dev-team --scope user   # ou --scope project
```

**2. Activer l'équipe dans un projet** — crée `<projet>/.omp/config.yml` :

```yaml
skills:
  enabled: true            # le marketplace fournit les skills + le corpus knowledge
task:
  disabledAgents: []       # ré-active les 32 agents si tu les désactives globalement
  maxRecursionDepth: 4     # orchestrator -> implémenteur -> explore
modelRoles:
  smol: claude-haiku-4-5   # ou ollama/qwen3-coder:30b (voir « Routage »)
  task: claude-sonnet-4-6
extensions:
  - ~/sources/omp-dev-team/.omp   # gardes (path-guard, review-gate…) + rules
```

`APPEND_SYSTEM.md` (le manuel d'équipe) se pose une fois en
`~/.omp/agent/APPEND_SYSTEM.md` (global) ou `<projet>/.omp/APPEND_SYSTEM.md`.

**Ce que le format plugin transporte — ou pas :**

| Brique | Livrée par | Comment |
|---|---|---|
| Agents, Skills, Knowledge, Commands, MCP | **marketplace** | `omp plugin install` — mis en cache, aucune copie, dispo dans tous les projets |
| Extensions (8 gardes + routage + telemetry) | **`extensions:` (par projet)** | pointe `extensions:` sur le `.omp/` d'un clone (chargées seulement là) |
| Rules (3) | **ne transitent pas** | ni plugin ni `extensions:` (testé) — substance déjà couverte, voir note |
| `modelRoles`, `APPEND_SYSTEM.md` | **config / fichier** | ne transitent pas par un plugin → à poser dans ta config |

> Pourquoi : un plugin marketplace découvre agents/skills/commands/MCP mais **pas**
> les modules d'extension TS ; `extensions:` (ou `omp plugin link <clone>/.omp`) charge
> les extensions, ce qui les garde **opt-in par projet** — c'est voulu : sinon
> `review-gate` bloquerait `git commit` dans **tous** tes autres repos. Les 3 **rules**
> ne transitent par aucun de ces chemins (vérifié) : mais `output-discipline` est déjà
> dans `APPEND_SYSTEM.md`, `tdd-first` est couvert par l'extension `tdd-guard`, et
> `agent-authoring` ne sert qu'en mode workspace. Pour les rules littérales, dépose
> `.omp/rules/` dans le projet (ou `~/.omp/agent/rules/` en global).

### Option B — workspace direct

Clone le repo et lance OMP dedans : `.omp/` est découvert automatiquement (tout
est actif, sans config opt-in).

```sh
git clone <ce-repo> omp-dev-team && cd omp-dev-team
omp
```

### Option C — copier `.omp/` dans un projet

```sh
cp -r omp-dev-team/.omp /chemin/vers/ton-projet/
cd /chemin/vers/ton-projet && omp
```

### Modèles locaux (9950X + 64 Go + RTX 5070 Ti 16 Go)

```sh
# 1. Ollama (auto-découvert par OMP sur 127.0.0.1:11434)
curl -fsSL https://ollama.com/install.sh | sh

# 2. Récupérer le modèle du petit palier (par défaut Qwen3-Coder-30B-A3B)
scripts/setup-local-models.sh          # + --fast pour aussi pull le 14B/7B

# 3. (option) contexte plus large / llama.cpp / LM Studio
cp models.yml.example ~/.omp/agent/models.yml
```

**Défaut : `qwen3-coder:30b` (Qwen3-Coder-30B-A3B)** — MoE 30,5 B total / ~3,3 B
actifs. Il ne tient pas entièrement dans 16 Go, mais en MoE Ollama décharge les
experts vers tes 64 Go de RAM et garde l'attention sur le GPU : plus malin qu'un
14B dense, et toujours rapide (~20–40 tok/s).

Variantes :
- **`qwen2.5-coder:14b`** (Q4, ~9 Go) — tient **entièrement** en VRAM, débit max
  pour le fan-out de revue parallèle. `scripts/setup-local-models.sh --fast`.
- **Perf max sur le 30B** : llama.cpp avec offload des experts —
  `scripts/setup-local-models.sh --flash` imprime la commande
  (`llama-server … --n-cpu-moe 28`), puis `modelRoles.smol: llama.cpp/qwen3-coder-30b-a3b`.

---

## Routage des modèles (le cœur)

Chaque agent déclare son palier dans son frontmatter `model:`. La source de
vérité est `skill://dev-team-knowledge/model-routing.json` ; le câblage est natif via
`.omp/config.yml` → `modelRoles`.

| Palier | Frontmatter | Résout vers | Agents |
|---|---|---|---|
| petit | `pi/smol` | **local** `ollama/qwen3-coder:30b` (`modelRoles.smol`) | naming, complexity, a11y, svelte, js-fp, token-efficiency, claude-setup, progress-guardian |
| équilibré | `claude-sonnet-4-6` | Sonnet (cloud) | orchestrator + la plupart des agents/revues |
| profond | `claude-opus-4-8` | Opus (cloud) | security-review, domain-review, arch-review, architect, security-engineer, codebase-recon |

**Basculer un palier** = une ligne dans `.omp/config.yml` :

```yaml
modelRoles:
  smol: ollama/qwen3-coder:30b           # local 30B-A3B (défaut, MoE)
  # smol: ollama/qwen2.5-coder:14b       # local, full-VRAM, débit max
  # smol: llama.cpp/qwen3-coder-30b-a3b  # 30B perf max (--n-cpu-moe)
  # smol: claude-haiku-4-5               # repasser ce palier en cloud
```

L'extension `model-routing` :
- **sonde** le backend local au démarrage de session ;
- **bloque** un dispatch de palier petit si le backend local est injoignable,
  avec un message d'action (réplique du `deny` du hook d'origine) ;
- **journalise** chaque dispatch dans `.omp/state/model-routing.log`.

Diagnostic : `/routing` (rapide) ou `/model-routing-check` (carte complète).

---

## Garde-fous (extensions = « scripts de blocage »)

| Extension | Commande(s) | Comportement |
|---|---|---|
| `model-routing` | `/routing` | gate de dispo du modèle local + log de dispatch |
| `path-guard` | — | **bloque** l'écriture de secrets/identifiants (`.env`, `*.pem`, `*secret*`…) |
| `destructive-guard` | — | avertit (ou **bloque** en mode careful) sur `rm -rf`, force-push, `DROP TABLE`… |
| `careful-mode` | `/careful on\|off\|status` | active le blocage destructif |
| `freeze-guard` | `/freeze <glob>` `/unfreeze` | verrouille des chemins contre l'édition |
| `tdd-guard` | — | rappel non bloquant RED-GREEN-REFACTOR |
| `review-gate` | `/review-approve` | **bloque `git commit`** tant que le set indexé n'est pas approuvé |
| `telemetry` | `/cost-report` | compteur de friction (tours, outils, contexte) par session |

Les extensions interceptent `tool_call` et renvoient `{ block, reason }` — c'est
le mécanisme de blocage natif d'OMP (cf. `docs/extensions.md` d'OMP).

---

## Pipeline (commandes)

```
/specs  →  /plan  →  /build  →  /pr
```

- `/specs` — intention, architecture, critères d'acceptation (gate de cohérence).
- `/plan` — découpe en tranches verticales + scénarios Gherkin ; 4 personas de
  revue de plan en parallèle avant le gate humain.
- `/build` — exécute le plan en TDD, revue inline 3 étapes, preuves de
  vérification ; `/code-review` puis `/review-approve` avant commit.
- `/pr` — gates qualité + ouverture de PR.

Autres : `/code-review` (`/review`), `/review-agent`, `/continue`, `/triage`,
`/design-doc`, `/issues-from-plan`, `/model-routing-check`, `/help`. Toute skill
portée est aussi disponible en `/skill:<nom>`.

---

## Personnalisation

- **Routage** : `.omp/config.yml` (`modelRoles`) + `skill://dev-team-knowledge/model-routing.json`.
- **Modèles locaux** : `models.yml.example` → `~/.omp/agent/models.yml`.
- **Garde-fous** : éditer les listes de motifs en tête de chaque extension.
- **MCP** : `.omp/.mcp.json` (et `.omp/mcp.json` en workspace) — activer `codegraph`/`github`, `enabled: true`.
- **Prompt système** : `.omp/APPEND_SYSTEM.md` (ajouté au prompt par défaut).

---

## État du portage

Portage du **cœur dev-team** : 32 agents, 78 skills, corpus de connaissance,
orchestration 3 phases, routage local, 8 extensions de blocage, commandes du
pipeline, MCP. Empaqueté pour OMP en **plugin marketplace** (`.claude-plugin/`,
plugin `dev-team@omp-dev-team`) ; les extensions se chargent en `extensions:`
opt-in et les 3 rules restent natives au workspace (leur substance est couverte
par `APPEND_SYSTEM.md` + l'extension `tdd-guard`). Le plugin compagnon
**security-assessment** (red-team ML, SARIF, mapping conformité) n'est pas inclus
dans cette vague.

Crédits : harness d'origine [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team)
(MIT, Bryan Finster) ; cible [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) (MIT).
