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
| **codebase-memory-mcp** | graphe de connaissances symboles/appels via MCP (158 langages, Hybrid LSP embarqué) — requête au lieu de grep+read | ~99 % sur « qui appelle X / impact / architecture » | [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) |
| **context7** | docs de librairies via MCP — docs API à jour à la demande | élimine les hallucinations sur les APIs de librairies | [upstash/context7](https://github.com/upstash/context7) |
| **caveman** | **sortie** laconique en fragments (à la demande) | ~65 % de tokens de sortie | [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) |
| **yagni** | écrire **moins de code** — YAGNI / dev sénior le plus fainéant (à la demande) | ~80–94 % de code en moins ; moins de tokens maintenant **et** à chaque tour futur | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| **mcp-as-cli-skill-creator** (skill) | un serveur MCP au schéma chargé injecte tout son schéma d'outils dans le prompt système à chaque requête | transforme un MCP / OpenAPI / GraphQL en CLI mince à l'exécution + skill à la demande, gardant son schéma **hors de la fenêtre de contexte** (le pattern ctx7/acli, généralisé) | skill OMP natif |
| **atlassian** (skill) | le travail Jira/Confluence nécessite un schéma MCP Atlassian toujours chargé, ou du `curl` fait main contre l'API REST | un skill (`skill://atlassian`) qui pilote le CLI `acli` déjà installé pour les lectures *et* écritures Jira/Confluence — recherche/vue/création/édition/commentaire/transition/lien d'issue, lectures de pages/espaces/blogs Confluence — déclenché automatiquement sur « Jira », « Confluence », une clé d'issue nue, ou une URL atlassian.net | skill OMP natif au-dessus du CLI officiel `acli` |
| **read-dedup** + **context-dedup** | relectures de fichiers inchangés + blocs identiques répétés gonflent l'**entrée** | SANS PERTE, actif : relecture → stub ; blocs byte-identiques fusionnés avant chaque appel | « Read Dedup » de caveman-code, réimplémenté sur les hooks `tool_call`/`context` d'OMP |
| **context-compress** | le **contexte prose** ancien reste verbeux à chaque tour | compression prose protect-maskée des vieux messages — code/chemins/nombres byte-identiques (`safe` actif par défaut ; `lite`/`full` opt-in) | version qualité-préservée du transform LLMLingua/Provence de [caveman-code](https://github.com/JuliusBrussee/caveman-code) |
| **cache-meter** | les économies de prompt-cache que tu *crois* avoir sont non mesurées — et un transform qui modifie le préfixe peut les casser en silence | LECTURE SEULE, actif : une **statusline** live (`td $coût cache N% churn N%`, ⚠ si risque) + `/cache-health` pour le détail (taux de lecture cache + churn + coût + part de thinking + quota provider) ; **alerte** quand la compression `lite`/`full` coïncide avec un fort churn | `usage` par-tour d'OMP (`turn_end`) + en-têtes `after_provider_response` + `ui.setStatus` |
| **Isolation providers** | exclut toutes les configs utilisateur d'autres outils du contexte OMP | élimine le bruit des agents Claude Code / Codex / Gemini / Cursor / Windsurf / Copilot / OpenCode | settings OMP natifs |
| **LSP C#** | `csharp-ls` câblé comme serveur de langage OMP natif — utilisé pour les sémantiques C# précises que le graphe ne peut pas fournir (rename, références exactes, diagnostics en direct, hover) | aller-à-la-définition, références, diagnostics sur `.cs`/`.csx` | [razzmatazz/csharp-language-server](https://github.com/razzmatazz/csharp-language-server) |

## Installation

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh   # installe ctx-wire + codebase-memory-mcp, indexe
                                     # vos repos, et active tout. Redémarrez omp ensuite.
```

**Actif par défaut après `install.sh`** — aucun réglage manuel : les shims ctx-wire
compressent la sortie des commandes, le serveur MCP codebase-memory-mcp est activé, et les
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
  **Redémarrage requis** : les shims atterrissent dans `~/.local/bin` ; un
  process OMP déjà lancé quand `install.sh` s'exécute garde son ancien PATH et
  ne les verra pas avant un redémarrage d'OMP (relancer l'installeur ne suffit
  pas). L'installeur sonde désormais un shell non-interactif frais juste après
  `ctx-wire shims install` et affiche un avertissement explicite si cette
  session est obsolète.
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
- **règle token-tools** → `rules/token-tools.md` (`alwaysApply: true`) est le
  guide de routage pour l'agent derrière tout ce qui précède : lancer les
  commandes sans préfixe, préférer codebase-memory-mcp à grep/glob/Read pour
  les questions structurelles, `csharp-ls` pour les sémantiques C# précises,
  `astEdit` plutôt que réécrire des fichiers entiers, et comment reconnaître
  une session avec shims obsolètes (pré-redémarrage). Le provider de règles
  d'OMP ne découvre automatiquement `rules/*.md` qu'à l'intérieur de racines
  de packages d'extension *configurées* — un simple install marketplace de ce
  plugin n'en est pas une — donc `install.sh`/`install.ps1` la recopient dans
  `~/.omp/agent/rules/token-diet-*.md` (même contournement que pour
  `extensions/` ci-dessous), où le provider natif d'OMP la scanne toujours.
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
- **acli** → le **CLI officiel Atlassian** (Jira/Confluence), installé dans
  `~/.local/bin` par `install.sh` (`--no-acli` pour sauter ; relancer pour mettre à
  jour — versions supportées ~6 mois). **acli est notre référence pour Atlassian** —
  en lecture comme en écriture, plutôt qu'un MCP Atlassian (aucun n'est enregistré).
  `install.sh` propose aussi de lancer `acli jira auth login` en interactif. Sortie
  anglaise/structurelle — `ctx-wire/filters.d/acli.toml` la compacte et masque les
  tokens `ATATT…` (ctx-wire scrube déjà GitHub/ADO/Atlassian en forme
  header/URL/`clé=valeur`). Le **skill `atlassian`** (`skill://atlassian`) est ce qui
  le pilote réellement : il enseigne à l'agent la surface de sous-commandes `acli
  jira`/`acli confluence` et se déclenche automatiquement sur « Jira », « Confluence »,
  une clé d'issue nue (`PROJ-123`), ou une URL `atlassian.net` — le même pattern de
  déclenchement automatique que le skill **context7** ci-dessous.
- **codebase-memory-mcp** → un serveur MCP (`.mcp.json`, binaire lancé en mode MCP,
  **activé par défaut**) exposant `search_graph`/`search_code`/`get_code_snippet`/
  `trace_path`/`get_architecture`/`query_graph`/`detect_changes`/`get_graph_schema`/
  `index_repository`/`index_status`/`list_projects`/`delete_project`/`manage_adr`/
  `ingest_traces` (158 langages, Hybrid LSP embarqué). Voir `skill://codebase-memory`.
  Se resynchronise aux changements de fichiers après le premier index. Pour les
  sémantiques C# précises que le graphe ne peut pas fournir (rename, références
  exactes, diagnostics en direct, hover), il s'appuie sur le LSP `csharp-ls` —
  voir la ligne **LSP C#**.
- **skills** → `install.sh` ajoute `config.snippet.yml` à `~/.omp/agent/config.yml`
  pour activer les skill commands et appliquer l'isolation des providers. `--no-config` pour sauter.
- **context7** → mode CLI (`ctx7 library` / `ctx7 docs` via bash — pas de process MCP).
  `install.sh` installe le CLI `ctx7` globalement. Le skill bundlé `context7`
  (`skill://context7`) instrut l'agent à récupérer les docs actuelles automatiquement
  dès qu'une librairie, un framework ou une API est impliqué.
- **mcp-as-cli-skill-creator** → un skill natif (`skill://mcp-as-cli-skill-creator`)
  qui **généralise le geste `ctx7`/`acli`** : à partir d'un serveur MCP (ou d'un
  endpoint OpenAPI / GraphQL), il génère un **CLI** mince à l'exécution
  (`~/.local/bin/<outil>`, une sous-commande par opération) plus un **skill doc**
  compagnon, et garde le serveur **hors de `.mcp.json`**. La capacité reste à un
  appel bash, tandis que son schéma JSON quitte le prompt système — au service
  direct de la surface d'outils maigre (`discoveryMode: all`). Fournit un squelette
  `references/cli-template.ts` (handshake JSON-RPC MCP-stdio + parsing d'args +
  sortie JSON compacte). Idéal pour les serveurs au schéma lourd peu appelés ; pas
  pour les outils du hot-path ou streaming/stateful.
- **Isolation providers** → `config.snippet.yml` positionne `disabledProviders` +
  `enableClaudeUser/Project/CodexUser: false` pour qu'OMP ne charge que ses propres
  plugins et les fichiers `AGENTS.md`/`CLAUDE.md` au niveau projet. Exclus : `~/.claude/plugins`,
  `~/.codex`, `~/.gemini`, `~/.cursor`, `~/.codeium/windsurf`, `~/.copilot`,
  `~/.config/opencode`, `.clinerules`. Les utilisateurs existants qui relancent
  `install.sh` reçoivent le bloc `disabledProviders` sans toucher aux autres réglages.
- **À noter côté fichier de contexte** → sans `~/.omp/agent/AGENTS.md`, OMP se
  rabat sur la lecture verbatim de `~/.claude/CLAUDE.md` au niveau utilisateur,
  y compris tout conseil propre à Claude Code qu'il contient (p. ex. un bloc
  injecté par ctx-wire disant à l'agent de préférer le shell brut aux outils
  natifs — correct pour Claude Code, faux pour OMP). `install.sh`/`install.ps1`
  affichent un avertissement ponctuel dans ce cas ; envisagez un `AGENTS.md`
  natif avec seulement les conventions qui s'appliquent réellement à OMP.
- **LSP C#** → `install.sh` installe `csharp-ls` via `dotnet tool install -g csharp-ls`
  (si le SDK .NET est présent) et écrit `~/.omp/agent/lsp.json`. OMP l'active
  automatiquement dès qu'un `.sln`/`.slnx`/`.csproj` est détecté. Il reste à côté de
  codebase-memory-mcp à dessein : le graphe de connaissances répond aux questions
  structurelles/inter-fichiers (y c. C#, via le Hybrid LSP embarqué), tandis que
  `csharp-ls` est un serveur de langage complet réservé aux besoins propres à C# que
  le graphe ne couvre pas — références exactes, rename, diagnostics/erreurs de type
  en direct, hover/signature, complétion.
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
- **cache-meter** → une extension en **lecture seule** (ne modifie jamais une
  requête) qui accumule l'`usage` par-tour d'OMP (`turn_end.message.usage` :
  input/output/**cacheRead/cacheWrite**/coût/thinking) plus les en-têtes de
  rate-limit du provider (`after_provider_response`). Elle tient une **statusline**
  live dans le footer via `ctx.ui.setStatus` (`td $<coût> cache <lecture%> churn
  <%>`, avec ⚠ en cas de risque — le coup d'œil permanent sur coût/santé cache),
  et `/cache-health` affiche le détail : **taux de lecture** du prompt-cache et
  **churn**, **coût** cumulé, part de thinking, % de fenêtre, et quota provider. Son intérêt : la
  boucle de contrôle du reste de token-diet — comme `context-compress`/les dedups
  réécrivent les **vieux** messages (exactement le préfixe stable qu'un provider
  met en cache KV), ils peuvent *augmenter* les économies visibles tout en
  *cassant* la lecture cache 10× moins chère. Le meter **alerte** quand une
  compression qui modifie le préfixe (`lite`/`full`) coïncide avec un fort churn,
  pour ne construire le gel-de-préfixe (« CacheAligner ») que si les chiffres le
  justifient (mesurer d'abord). Couper (tout le meter) : `TOKEN_DIET_CACHE_METER=off`,
  ou silencier juste la ligne du footer : `TOKEN_DIET_CACHE_STATUSLINE=off`. Math
  pure dans `extensions/lib/cache-stats.ts`, testée. (OMP expose cet usage aux
  extensions aujourd'hui — l'ancienne hypothèse « pas dispo dans les hooks » ne
  tient plus.)

## Ce qu'OMP fait déjà (pour ne pas doublonner)

Compaction/handoffs (résumé de l'historique), outils AST natifs (`astGrep`,
`astEdit`, `summarizeCode`, `blockRangeAt`), et mise en cache prompts/contexte côté
fournisseur. Ce plugin comble les trous restants : sortie brute des commandes,
graphe de symboles persistant inter-fichiers, et sortie verbeuse du modèle. Voir
`skill://token-diet` pour le guide de décision complet.

## Notes

- Se marie naturellement avec **copilot-preset** (modèles peu chers au token) —
  moins de tokens × tokens moins chers.
- Le serveur MCP de graphe de code (anciennement CodeGraph) est centralisé ici en
  tant que codebase-memory-mcp ; `dev-team/.mcp.json` ne porte aucune entrée de
  graphe de code.
- Indépendant des autres plugins ; n'installez que ce que vous voulez.
