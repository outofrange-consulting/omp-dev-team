# dev-team

> 🌐 [English](README.md) · **Français**

Une **équipe de développement agentique** pour [Oh-My-Pi](https://github.com/can1357/oh-my-pi),
portée depuis [bdfinst/agentic-dev-team](https://github.com/bdfinst/agentic-dev-team)
de Bryan Finster. Un orchestrateur aiguille le travail à travers un workflow
**spec → plan → build → PR** avec un **plan-gate forcé** (pré-analyse → plan →
build → review), **tests requis** et **points de contrôle humains**, appuyé par 32
agents spécialistes et critiques et des extensions garde-fou bloquantes.

> Philosophie (Finster) : l'IA est un filtre passe-haut pour la discipline
> d'ingénierie. Le gain vient de la livraison continue et du fait de définir ce
> qu'on construit avant de le construire — pas du choix du modèle. Ce plugin
> encode cette discipline sous forme d'un plan-gate forcé + les tests comme filet
> de sécurité. (L'ordonnancement test-first/TDD n'est **pas** imposé — il apporte
> peu aux agents IA ; le levier est le plan-gate.)

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
2. **`/plan`** — transformer la spec approuvée en plan d'étapes (chaque tranche
   nomme ses tests). Cinq **critiques de revue de plan** (test d'acceptation,
   design, UX, stratégique, parallélisation) le challengent en parallèle *avant*
   que vous ne le voyiez. Approuvez avec **`/plan-approve`** pour débloquer le
   build (`plan-gate`) ; pour une tâche vraiment triviale, `/scope --trivial`.
3. **`/build`** — exécuter le plan approuvé, tranches indépendantes en parallèle
   par vagues. Tests requis par unité (test-first optionnel), vérifiés au vert
   par **`/impl-verify`**.
4. **`/pr`** — passer les portes qualité et ouvrir la pull request.

Pour les tâches complexes, l'**orchestrateur** déroule **Research → Plan →
Implement** avec un point de contrôle humain entre les phases. Plus `/code-review`
(`/review`), `/review-agent`, `/continue`, `/triage`, `/design-doc`,
`/issues-from-plan`, et le diagnostic `/routing`. Chaque skill est aussi
disponible en `/skill:<nom>`.

## Tiers de modèles (tous cloud, orientés-workload)

Les agents déclarent un tier dans leur frontmatter `model:`, résolu nativement par
vos `modelRoles`. Le bas de gamme est **scindé par forme de workload** pour
qu'aucune moitié ne surpaie le modèle de l'autre :

| Tier | Frontmatter | Pour |
|---|---|---|
| nano | `pi/smol` (cloud le moins cher ; Haiku, ou gpt-5-mini sur Copilot) | revue purement lexicale/checklist + scan input-bound — pas de sémantique code ni de tool-use ; plus gros volume |
| code | `pi/task` (cloud coding bon marché ; Haiku, ou mai-code-1-flash sur Copilot) | travail cheap nécessitant de la sémantique code ou du tool-use agentique : implémentation post-plan, revue structurelle |
| balanced | `claude-sonnet-4-6` | la plupart des agents d'équipe et de revue, l'orchestrateur, codebase-recon |
| deep | `claude-opus-4-8` | raisonnement multi-fichiers à fort enjeu, synthèse de design, threat modeling |

Les tiers **nano + code** à gros volume sont là où la dépense de tokens se
concentre — gardez-les bon marché. Sur Anthropic de base, les deux résolvent vers
Haiku ; le plugin **copilot-preset** les scinde (`smol` → `github-copilot/gpt-5-mini`,
`task` → `github-copilot/mai-code-1-flash`). Combinez avec **token-diet** pour
réduire encore les tokens. Source de vérité :
`skills/dev-team-knowledge/model-routing.json` ; diagnostic via `/routing`.

## Garde-fous (extensions)

`plan-gate` (**bloque l'édition du code source tant que la tâche n'est pas cadrée
et un plan approuvé** — impose pré-analyse → plan → build → review ; `/scope`,
`/trivial`, `/plan-approve`, `/plan-reset`), `path-guard` (secrets),
`destructive-guard` + `/careful`, `freeze-guard` (`/freeze` `/unfreeze`),
`spec-guard` (**bloque l'édition des specs `.feature` existantes** — on corrige le
code, pas la spec ; `/allow-feature-edits` pour outrepasser), `review-gate` (bloque
`git commit` jusqu'à `/code-review` + `/review-approve`), `impl-verify`
(`/impl-verify` build strict + tests), `telemetry` + `/cost-report`,
`model-routing` (log de tier des dispatches + `/routing`). Elles interceptent
`tool_call` et bloquent avec un motif — le mécanisme de blocage natif d'OMP.

## Disposition

```
.claude-plugin/plugin.json · package.json (omp.extensions)
agents/  skills/  commands/  rules/  extensions/  .mcp.json
skills/dev-team-knowledge/   # registres, rubriques, model-routing.json
config.snippet.yml  install.sh  install.ps1
```
