# dev-team

> 🌐 [English](README.md) · **Français**

Une **équipe de développement agentique** pour [Oh-My-Pi](https://github.com/can1357/oh-my-pi),
portée depuis [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team)
de Bryan Finster. Un orchestrateur aiguille le travail à travers un workflow
**spec → plan → build → PR** avec **TDD strict** et **points de contrôle humains**,
appuyé par 32 agents spécialistes et critiques et des extensions garde-fou bloquantes.

> Philosophie (Finster) : l'IA est un filtre passe-haut pour la discipline
> d'ingénierie. Le gain vient de la livraison continue, du TDD, et du fait de
> définir ce qu'on construit avant de le construire — pas du choix du modèle. Ce
> plugin encode cette discipline.

## Installation

```sh
omp plugin marketplace add outofrange-consulting/omp-dev-team
omp plugin install dev-team@omp-dev-team
```

Puis collez `config.snippet.yml` dans `~/.omp/agent/config.yml` (routage des
modèles + `skills.enableSkillCommands` + le graphe de tâches). Le vérificateur de
prérequis du plugin :

```sh
bash plugins/dev-team/install.sh        # vérifie OMP/git/outils optionnels, peut appliquer la config
```

## Le workflow

`/specs` → `/plan` → `/build` → `/pr` :

1. **`/specs`** — capturer une fonctionnalité : Intention + scénarios BDD +
   Architecture + Critères d'acceptation. L'humain approuve.
2. **`/plan`** — transformer la spec approuvée en plan d'étapes TDD. Quatre
   **critiques de revue de plan** (test d'acceptation, design, UX, stratégique)
   le challengent en parallèle *avant* que vous ne le voyiez.
3. **`/build`** — exécuter le plan approuvé sous des barrières strictes
   **RED → GREEN → REFACTOR** (`tdd-guard`).
4. **`/pr`** — passer les portes qualité et ouvrir la pull request.

Pour les tâches complexes, l'**orchestrateur** déroule **Research → Plan →
Implement** avec un point de contrôle humain entre les phases. Plus `/code-review`
(`/review`), `/review-agent`, `/continue`, `/triage`, `/design-doc`,
`/issues-from-plan`, `/model-routing-check`. Chaque skill est aussi disponible en
`/skill:<nom>`.

## Tiers de modèles (tous cloud)

Les agents déclarent un tier dans leur frontmatter `model:`, résolu nativement par
vos `modelRoles` :

| Tier | Frontmatter | Pour |
|---|---|---|
| small | `pi/smol` (cloud bon marché, Haiku par défaut) | vérifs lexicales/structurelles, revues par checklist — gros volume |
| balanced | `claude-sonnet-4-6` | la plupart des agents d'équipe et de revue, l'orchestrateur |
| deep | `claude-opus-4-8` | raisonnement multi-fichiers, synthèse de design, threat modeling, recon |

Le tier **small** à gros volume est là où la dépense de tokens se concentre —
gardez-le bon marché. Pointez `modelRoles.smol` vers `claude-haiku-4-5`, ou (avec
le plugin **copilot-preset**) vers `github-copilot/gpt-5-mini` pour le faire
tourner sur votre licence Copilot. Combinez avec **token-diet** pour réduire encore
les tokens. Source de vérité : `skills/dev-team-knowledge/model-routing.json` ;
diagnostic via `/routing` ou `/skill:model-routing-check`.

## Garde-fous (extensions)

`path-guard` (secrets), `destructive-guard` + `/careful`, `freeze-guard`
(`/freeze` `/unfreeze`), `tdd-guard` (nudge RED-GREEN-REFACTOR + **bloque l'édition
des specs `.feature` existantes** — on corrige le code, pas les tests ;
`/allow-feature-edits` pour outrepasser), `review-gate` (bloque
`git commit` jusqu'à `/code-review` + `/review-approve`), `telemetry` +
`/cost-report`, `model-routing` (log de tier des dispatches + `/routing`). Elles
interceptent `tool_call` et bloquent avec un motif — le mécanisme de blocage natif
d'OMP.

## Disposition

```
.claude-plugin/plugin.json · package.json (omp.extensions)
agents/  skills/  commands/  rules/  extensions/  .mcp.json
skills/dev-team-knowledge/   # registres, rubriques, model-routing.json
config.snippet.yml  install.sh  install.ps1
```
