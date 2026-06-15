# token-diet

> 🌐 [English](README.md) · **Français**

**Réduction agressive des tokens** pour les équipes OMP. Regroupe trois économiseurs
de tokens externes de premier plan et les câble à OMP de façon native — par-dessus
ce qu'OMP fait déjà (compaction, `astGrep`/`summarizeCode`, mise en cache des
prompts côté fournisseur), pas à la place.

| Couche | Quoi | Gain | Amont |
|---|---|---|---|
| **ctx-wire** | proxy CLI transparent qui filtre la **sortie** des commandes + scrube les secrets (logs complets sur disque) | grosses coupes sur le bruit `git`/build/test/lint | [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire) |
| **CodeGraph** | graphe de symboles/appels via MCP — requête au lieu de grep+read | ~96 % sur « qui appelle X / impact / architecture » | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) |
| **caveman** | **sortie** laconique en fragments (à la demande) | ~65 % de tokens de sortie | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | écrire **moins de code** — YAGNI / dev sénior le plus fainéant (à la demande) | ~80–94 % de code en moins ; moins de tokens maintenant **et** à chaque tour futur | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |

## Installation

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installe ctx-wire + codegraph, indexe vos repos,
                                     # et active tout. Redémarrez omp ensuite.
```

**Actif par défaut après `install.sh`** — aucun réglage manuel : les shims ctx-wire
compressent la sortie des commandes, le serveur MCP CodeGraph est activé, et les
skills sont activés. `install.sh` demande la **racine de vos sources** (un dossier
de plusieurs repos) et indexe chaque repo git trouvé (`--sources-root=PATH`, `--depth=N`).

## Comment c'est câblé dans OMP

- **ctx-wire** → installé par `install.sh`, puis **`ctx-wire shims install`** dépose
  des wrappers transparents dans `~/.local/bin` (en tête du PATH, hérité par l'outil
  bash d'OMP) : l'agent lance les commandes normalement — **sans préfixe** — et leur
  sortie est filtrée + les secrets scrubés avant d'atteindre le contexte (logs
  complets sur disque). (`ctx-wire init claude` ne câble que Claude Code, pas OMP —
  d'où les shims.) `ctx-wire gain` montre les économies ; `ctx-wire doctor` vérifie.
- **CodeGraph** → un serveur MCP (`.mcp.json`, `codegraph serve --mcp`, **activé par
  défaut**) exposant `codegraph_search/node/callers/callees/explore/impact/files/status`.
  Voir `skill://codegraph`. Se resynchronise aux changements de fichiers.
- **skills** → `install.sh` ajoute `config.snippet.yml` à `~/.omp/agent/config.yml`
  (`skills.enableSkillCommands: true`) pour que `/caveman`, `/yagni` et
  `skill://codegraph` soient disponibles (requis pour les skills de plugin). `--no-config` pour sauter.
- **caveman** → un skill OMP natif (`/caveman`, niveaux lite/full/ultra) plutôt que
  l'installeur amont, pour être de première classe dans OMP. Voir `skill://caveman`.
- **yagni** → un skill OMP natif (`/yagni`, niveaux lite/full/ultra/off) qui porte
  la discipline YAGNI « dev sénior le plus fainéant » de ponytail : une échelle
  *est-ce que j'ai vraiment besoin d'écrire ça* + modes review/audit/debt. Fainéant
  ≠ négligent — sécurité/validation/perte-de-données/a11y/tests jamais sacrifiés (et
  il ne modifie pas les specs `.feature` pour éviter le travail). Voir `skill://yagni`.

## Ce qu'OMP fait déjà (pour ne pas doublonner)

Compaction/handoffs (résumé de l'historique), outils AST natifs (`astGrep`,
`astEdit`, `summarizeCode`, `blockRangeAt`), et mise en cache prompts/contexte côté
fournisseur. Ce plugin comble les trous restants : sortie brute des commandes,
graphe de symboles persistant inter-fichiers, et sortie verbeuse du modèle. Voir
`skill://token-diet` pour le guide de décision complet.

## Notes

- Se marie naturellement avec **copilot-preset** (modèles peu chers au token) —
  moins de tokens × tokens moins chers.
- L'entrée CodeGraph qui traînait (désactivée) dans `dev-team/.mcp.json` est
  maintenant centralisée ici avec la bonne invocation `serve --mcp`.
- Indépendant des autres plugins ; n'installez que ce que vous voulez.
