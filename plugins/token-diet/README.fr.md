# token-diet

> 🌐 [English](README.md) · **Français**

**Réduction agressive des tokens** pour les équipes OMP. Regroupe trois économiseurs
de tokens externes de premier plan et les câble à OMP de façon native — par-dessus
ce qu'OMP fait déjà (compaction, `astGrep`/`summarizeCode`, mise en cache des
prompts côté fournisseur), pas à la place.

| Couche | Quoi | Gain | Amont |
|---|---|---|---|
| **ctx-wire** | proxy CLI transparent qui filtre la **sortie** des commandes + scrube les secrets (logs complets sur disque) ; surcharges de filtres **EN+FR** pour `git status` + `dotnet build`/`test` (VSTest & MTP)/`restore`/`run`/`tool` | grosses coupes sur le bruit `git`/build/test/lint | [pivanov/ctx-wire](https://github.com/pivanov/ctx-wire) |
| **context-mode** | plugin OMP natif qui **met la sortie des outils en bac à sable** et l'indexe (FTS5/BM25, indépendant de la langue) — garde le brut hors contexte + survit à la compaction | ~98 % sur sortie géante/non structurée ; toute langue (y c. ro) | [mksglu/context-mode](https://github.com/mksglu/context-mode) |
| **CodeGraph** | graphe de symboles/appels via MCP — requête au lieu de grep+read | ~96 % sur « qui appelle X / impact / architecture » | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) |
| **context7** | docs de librairies via MCP — docs API à jour à la demande | élimine les hallucinations sur les APIs de librairies | [upstash/context7](https://github.com/upstash/context7) |
| **caveman** | **sortie** laconique en fragments (à la demande) | ~65 % de tokens de sortie | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | écrire **moins de code** — YAGNI / dev sénior le plus fainéant (à la demande) | ~80–94 % de code en moins ; moins de tokens maintenant **et** à chaque tour futur | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **read-dedup** + **context-dedup** | relectures de fichiers inchangés + blocs identiques répétés gonflent l'**entrée** | SANS PERTE, actif : relecture → stub ; blocs byte-identiques fusionnés avant chaque appel | « Read Dedup » de caveman-code, réimplémenté sur les hooks `tool_call`/`context` d'OMP |
| **context-compress** | le **contexte prose** ancien reste verbeux à chaque tour | compression prose protect-maskée des vieux messages — code/chemins/nombres byte-identiques (`safe` actif par défaut ; `lite`/`full` opt-in) | version qualité-préservée du transform LLMLingua/Provence de [caveman-code](https://github.com/JuliusBrussee/caveman-code) |
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
  Remplace l'intégration RTK précédente (RTK est aussi anglais-only : aucun gain
  de localisation).
  **Filtres multilingues** → `install.sh` fusionne des surcharges EN+FR
  (`ctx-wire/filters.d/`) pour `git status` / `dotnet build` / `dotnet test` dans
  `~/.config/ctx-wire/filters.toml`, pour que la même compaction se déclenche en
  locale `fr_*` (chaînes FR reprises telles quelles de la localisation
  git/MSBuild/VSTest). Seuls git+dotnet sont localisés : tous les autres filtres
  ctx-wire sont soit structurels (grep, git-log, ls), soit enveloppent une
  toolchain anglais-only (npm/cargo/go/…). **Pas de roumain** — git et .NET ne
  livrent aucune traduction `ro`, donc ils émettent de l'anglais en locale
  `ro_RO` ; le roumain n'apparaît que dans les *données*, gérées par context-mode.
  Voir `ctx-wire/README.md`.
- **context-mode** → `omp plugin install context-mode` (lancé par `install.sh`,
  `--no-context-mode` pour sauter). Plugin OMP natif sur les hooks
  `tool_call`/`tool_result`/`session_start`/`session_before_compact` qui met la
  sortie des outils en bac à sable et l'indexe (FTS5/BM25, indépendant de la
  langue) — le filet locale-agnostique pour toute sortie non anglaise (y c. le
  roumain) et pour la continuité de session à travers la compaction. Se superpose
  aux collapses déterministes de ctx-wire, sans les remplacer. Il compresse aussi
  la sortie **MCP** (il s'accroche à `tool_result`) — donc les gros JSON des MCP
  Atlassian/Miro/GitHub sont réduits, ce que les shims ctx-wire (bash uniquement)
  ne voient pas. Pour les serveurs MCP que tu définis toi-même : `ctx-wire mcp-wrap
  --compress` ; voir `ctx-wire/README.md`.
- **acli** → le **CLI officiel Atlassian** (Jira/Confluence/Bitbucket), installé dans
  `~/.local/bin` par `install.sh` (`--no-acli` pour sauter ; relancer pour mettre à
  jour — versions supportées ~6 mois). Préfère le **MCP Atlassian** pour les lectures
  structurées ; `acli` pour les écritures en masse/scriptées. Sortie anglaise/
  structurelle — `ctx-wire/filters.d/acli.toml` la compacte et masque les tokens
  `ATATT…` (ctx-wire scrube déjà GitHub/ADO/Atlassian en forme header/URL/`clé=valeur`).
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
- **read-dedup / context-dedup / context-compress** → des extensions OMP natives,
  recopiées dans `~/.omp/agent/extensions/token-diet` par `install.sh` (OMP ne
  charge pas les extensions depuis un install cache de marketplace). Les deux
  **dedups sont sans perte et actifs par défaut** : read-dedup intercepte l'outil
  `read` (`tool_call`) et renvoie un stub à la relecture byte-identique d'un
  fichier inchangé (et tient compte de la compaction) ; context-dedup utilise le
  hook `context` pour fusionner les blocs byte-identiques répétés entre messages
  outil/assistant (en gardant le plus récent verbatim) — y compris les doublons
  venant de `bash`/`cat` et des MCP. **context-compress tourne en `safe` par
  défaut** (quasi sans perte : strip ANSI + collapse des espaces uniquement, aucun
  mot supprimé) : la réalisation qualité-préservée du transform de contexte
  LLMLingua/Provence de caveman-code. Un *protect mask* garde le code, les chemins,
  les nombres et les identifiants **byte-identiques** (le même ensemble qu'on
  passerait à un vrai LLMLingua-2 en `force_tokens`), seule la prose est touchée,
  et la fenêtre de récence + tous les messages user/system sont laissés intacts.
  Pour aller plus loin (lossy — supprime filler/articles) ou couper :
  `TOKEN_DIET_CONTEXT_COMPRESS=lite|full|off`. Logique pure dans `extensions/lib`,
  testée par `bun scripts/extensions.test.ts`. Analyse complète + voie d'escalade
  vers le vrai LLMLingua : `research/caveman-code.md`.

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
