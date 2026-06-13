# token-diet

> 🌐 [English](README.md) · **Français**

**Réduction agressive des tokens** pour les équipes OMP. Regroupe trois économiseurs
de tokens externes de premier plan et les câble à OMP de façon native — par-dessus
ce qu'OMP fait déjà (compaction, `astGrep`/`summarizeCode`, mise en cache des
prompts côté fournisseur), pas à la place.

| Couche | Quoi | Gain | Amont |
|---|---|---|---|
| **RTK** | Rust Token Killer — proxy CLI qui compresse la **sortie** des commandes | 60–90 % sur `git`/`grep`/`find`/`test` | [rtk-ai/rtk](https://github.com/rtk-ai/rtk) |
| **CodeGraph** | graphe de symboles/appels via MCP — requête au lieu de grep+read | ~96 % sur « qui appelle X / impact / architecture » | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) |
| **caveman** | **sortie** laconique en fragments (à la demande) | ~65 % de tokens de sortie | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |

## Installation

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installe rtk + codegraph, puis demande votre
                                     # RACINE de sources et indexe CHAQUE repo git dessous
```

`install.sh` demande la **racine de vos sources** (un dossier contenant plusieurs
repos) et indexe chaque repo git trouvé (`--sources-root=PATH`, `--depth=N`), pour
que n'importe quel repo soit prêt dès que vous l'ouvrez. Activez ensuite le serveur
MCP CodeGraph (livré `enabled: false`) : mettez `mcpServers.codegraph.enabled = true`
dans votre `.mcp.json` fusionné.

## Comment c'est câblé dans OMP

- **RTK** → une **règle toujours active** (`rules/token-tools.md`) dit à l'agent de
  lancer les commandes shell verbeuses en `rtk <cmd>`. RTK est CLI seulement (pas de
  MCP) ; OMP n'est pas une cible de `rtk init`, donc la règle est l'intégration.
  Dégrade proprement si `rtk` n'est pas installé.
- **CodeGraph** → un serveur MCP (`.mcp.json`, `codegraph serve --mcp`) exposant
  `codegraph_search/node/callers/callees/explore/impact/files/status`. Voir
  `skill://codegraph`. Se resynchronise automatiquement aux changements de fichiers.
- **caveman** → un skill OMP natif (`/caveman`, niveaux lite/full/ultra) plutôt que
  l'installeur amont, pour être de première classe dans OMP. Voir `skill://caveman`.

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
