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
bash plugins/dev-team/install.sh        # vérifie OMP/git/outils optionnels, installe .NET 10+ pour serena-forge, peut appliquer la config
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
et `/issues-from-plan`. Chaque skill est aussi
disponible en `/skill:<nom>`.

## Tiers de modèles (100 % cloud, par forme de charge, ouverts sur les fournisseurs)

Les agents déclarent une **liste de rôles** dans le frontmatter `model:`. OMP prend
le **premier motif résoluble**, donc chaque agent termine sa liste par `@default`
et route même si vous n'avez jamais collé le snippet de config. Le bas de gamme est
scindé par **forme de charge**, pour qu'aucune moitié ne paie le modèle de l'autre :

| Tier | Frontmatter | Pour |
|---|---|---|
| nano | `"@smol, @default"` | revue purement lexicale/checklist + scan input-bound — pas de sémantique code ni de tool-use ; plus gros volume |
| code | `"@smol, @default"` | travail bon marché nécessitant sémantique code ou tool-use agentique : implémentation post-plan (software-engineer, qa-engineer), revue structurelle (js-fp, svelte), codebase-recon |
| balanced | `"@plan, @default"` | la plupart des agents de revue + l'orchestrateur + les agents d'équipe hors-build |
| design | `"@designer, @plan, @default"` | travail UI/UX et accessibilité — `designer` est un rôle OMP de première classe qu'on laissait mort |
| deep | `"@slow, @plan, @default"` | synthèse de design archi/domaine et verdicts de sécurité à fort enjeu |

Deux faits OMP motivent ce découpage et méritent d'être connus :

- **`@task` n'est *pas* un tier bon marché.** Il hérite délibérément de la session
  (`model-resolver.ts:936-943`) : les agents qui le déclaraient tournaient donc sur
  le modèle de session, pas sur un modèle cheap. Ils déclarent désormais `@smol`.
- **Seuls `smol`, `slow` et `designer` héritent de `default`**
  (`model-resolver.ts:946`). Un `modelRoles.plan` non défini retombe donc
  **silencieusement** sur le modèle de session — d'où le snippet livré qui pose
  `plan` et `task` explicitement au lieu de compter sur l'héritage.

Aucun agent ne fige d'id de modèle fournisseur. Sur Anthropic direct les rôles
résolvent vers Haiku/Sonnet/Opus ; le plugin **copilot-preset** superpose des
modèles servis par Copilot, et n'importe quel fournisseur compatible OpenAI passe
par **openai-compatible**. Il n'y a plus de résolveur côté plugin : le harness
résout `modelRoles` lui-même (voir `docs/upstream-v8-v10.md` pour la raison du
retrait du résolveur de bandes).

## Garde-fous (extensions)

`plan-gate` (**bloque l'édition du code source tant que la tâche n'est pas cadrée
et un plan approuvé** — impose pré-analyse → plan → build → review ; `/scope`,
`/trivial`, `/plan-approve`, `/plan-reset`), `path-guard` (secrets),
`destructive-guard` + `/careful`, `freeze-guard` (`/freeze` `/unfreeze`),
`spec-guard` (**bloque l'édition des specs `.feature` existantes** — on corrige le
code, pas la spec ; `/allow-feature-edits` pour outrepasser), `review-gate` (bloque
`git commit` jusqu'à `/code-review` + `/review-approve`), `impl-verify`
(`/impl-verify` build strict + tests), `telemetry` + `/cost-report`,
et `telemetry` + `/cost-report`. Elles interceptent
`tool_call` et bloquent avec un motif — le mécanisme de blocage natif d'OMP.

## Disposition

```
.claude-plugin/plugin.json · package.json (omp.extensions)
agents/  skills/  commands/  rules/  extensions/  .mcp.json
skills/dev-team-knowledge/   # registres (générés), rubriques, tarifs
config.snippet.yml  install.sh  install.ps1
```
