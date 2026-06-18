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
| **context7** | docs de librairies via MCP — docs API à jour à la demande | élimine les hallucinations sur les APIs de librairies | [upstash/context7](https://github.com/upstash/context7) |
| **caveman** | **sortie** laconique en fragments (à la demande) | ~65 % de tokens de sortie | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | écrire **moins de code** — YAGNI / dev sénior le plus fainéant (à la demande) | ~80–94 % de code en moins ; moins de tokens maintenant **et** à chaque tour futur | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **Isolation providers** | exclut toutes les configs utilisateur d'autres outils du contexte OMP | élimine le bruit des agents Claude Code / Codex / Gemini / Cursor / Windsurf / Copilot / OpenCode | settings OMP natifs |
| **LSP C#** | `csharp-ls` câblé comme serveur de langage OMP natif | aller-à-la-définition, références, diagnostics sur `.cs`/`.csx` | [razzmatazz/csharp-language-server](https://github.com/razzmatazz/csharp-language-server) |

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
  pour activer les skill commands et appliquer l'isolation des providers. `--no-config` pour sauter.
- **context7** → mode CLI (`ctx7 library` / `ctx7 docs` via bash — pas de process MCP).
  `install.sh` installe le CLI `ctx7` globalement. Le skill bundlé `context7`
  (`skill://context7`) instrut l'agent à récupérer les docs actuelles automatiquement
  dès qu'une librairie, un framework ou une API est impliqué.
- **Isolation providers** → `config.snippet.yml` positionne `disabledProviders` +
  `enableClaudeUser/Project/CodexUser: false` pour qu'OMP ne charge que ses propres
  plugins et les fichiers `AGENTS.md`/`CLAUDE.md` au niveau projet. Exclus : `~/.claude/plugins`,
  `~/.codex`, `~/.gemini`, `~/.cursor`, `~/.codeium/windsurf`, `~/.copilot`,
  `~/.config/opencode`, `.clinerules`. Les utilisateurs existants qui relancent
  `install.sh` reçoivent le bloc `disabledProviders` sans toucher aux autres réglages.
- **LSP C#** → `install.sh` installe `csharp-ls` via `dotnet tool install -g csharp-ls`
  (si le SDK .NET est présent) et écrit `~/.omp/agent/lsp.json`. OMP l'active
  automatiquement dès qu'un `.sln`/`.slnx`/`.csproj` est détecté.
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
