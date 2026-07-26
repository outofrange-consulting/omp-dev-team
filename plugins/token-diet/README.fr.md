# token-diet

> 🌐 [English](README.md) · **Français**

**v2.0.0 — recentré.** Ce plugin était une couche d'exécution posée sur OMP :
dédup de lectures, dédup de contexte, un compteur de cache de prompt, une
« surface d'outils maigre ». OMP 17.x livre tout ça nativement. Ce qui reste est
l'ensemble étroit de choses que le harness ne fait genuinement pas — et rien ici
ne le double.

| Couche | Quoi | Pourquoi ça survit |
|---|---|---|
| **filtres ctx-wire** (4) | filtres EN+FR pour `dotnet publish` / `pack` / `run` / `tool` | OMP tronque *mécaniquement* (fenêtre de queue, plafond de colonne, déversement en artefact). Seuls ces filtres savent qu'un `dotnet publish` tout-vert de 20 Ko se réduit à une ligne d'artefact — et seuls eux le savent **en français**. Les filtres Rust d'OMP couvrent déjà `git` et `dotnet build\|test\|restore\|format` : on ne livre donc ni l'un ni l'autre. |
| **caveman** (skill) | **sortie** laconique en fragments, à la demande | Le seul levier qui vise les tokens de **sortie**. Rien dans OMP — ni dans agentic-dev-team en amont — ne touche à ce que le modèle écrit. Ne coûte que son nom + sa description tant qu'il n'est pas invoqué. |
| **path-inject** (extension) | préfixe `~/.local/bin` au `PATH` dans le process OMP | OMP lance bash en non-login/non-interactif : `~/.profile` n'est jamais sourcé, et un shim ctx-wire fraîchement installé reste invisible jusqu'à l'ouverture d'un nouveau terminal. 32 lignes, aucun hook, aucune mutation de message. |
| **context-compress** (extension) | compression prose protect-maskée des vieux messages | **DÉSACTIVÉ par défaut, opt-in.** Gardé comme expérience instrumentée, pas comme fonctionnalité — voir l'avertissement plus bas. |
| **règle token-tools** | ~15 lignes, `alwaysApply` | ctx-wire est transparent ; `read`/`grep`/`astEdit` restent supérieurs au shell brut ; éditer les symboles structurellement. |
| **isolation providers + réglages natifs** | `config.snippet.yml` | `disabledProviders` plus la poignée de réglages OMP qui paient vraiment aujourd'hui (ci-dessous). |

## Ce qu'OMP fait nativement (donc pas ce plugin)

| Natif | Défaut | Remplace, dans ce plugin |
|---|---|---|
| `compaction.supersedeReads` | **actif** | `read-dedup` + `context-dedup`. Et le natif est *meilleur* : il garde la lecture **la plus récente** et blanchit l'ancienne ; le nôtre bloquait la plus récente et forçait le modèle sur des octets périmés. |
| `compaction.dropUseless`, `pruneToolOutputs` | **actif** / intégré | le reste de l'histoire de la dédup |
| filtres Rust `shellMinimizer` | **actif** | nos filtres `git-status` / `dotnet-build` / `dotnet-test` / `dotnet-restore` |
| segments de statusline `cost` / `cache_read` / `cache_write` / `cache_hit` / `context_pct` / `usage` | segments | `cache-meter` et `/cache-health` — ainsi que le fork, par l'installeur, du propre rendu de statusline d'OMP, cassé de toute façon |
| `secrets.enabled` + `~/.omp/agent/secrets.yml` | off → **on l'active** | l'étape de masquage de tokens de l'ancien filtre `acli` — et il couvre le cas qu'un filtre de sortie de commande ne pouvait pas voir : un secret arrivé par `read .env` ou par un résultat MCP |
| `tools.xdev` | **actif** | `tools.discoveryMode` / `tools.essentialOverride` (REMOVED en OMP 17.0.0 et désormais silencieusement supprimés de votre config au chargement) et le skill `mcp-as-cli-skill-creator` bâti sur leur prémisse |
| `lsp` + `omnisharp` intégré | auto | tout outillage C# que ce plugin installait |

**Règle de conception qui en découle :** ne pas construire de transformation de
contexte côté plugin. Réécrire les **vieux** messages modifie le préfixe que le
fournisseur met en cache KV, et l'entrée en cache est ~10× moins chère que
l'entrée fraîche — casser le cache coûte plus que les octets économisés.

## Où sont parties les pièces retirées

| Retiré | Désormais |
|---|---|
| skill `atlassian` + install/auth `acli` + `acli.toml` | le **serveur MCP distant officiel Atlassian** (`https://mcp.atlassian.com/v1/mcp/authv2`, OAuth), câblé par l'installeur racine |
| skill `context7` + install du CLI `ctx7` | le **serveur MCP distant officiel Context7** (`https://mcp.context7.com/mcp`, en-tête `CONTEXT7_API_KEY`), câblé par l'installeur racine |
| skill `yagni` | **supprimé** |
| skill `mcp-as-cli-skill-creator` | supprimé — sa prémisse (« les schémas MCP coûtent du contexte, emballons-les en CLI ») est morte avec `tools.xdev` |
| extensions `read-dedup`, `context-dedup`, `cache-meter`, `/cache-health` | supprimées — natif (tableau ci-dessus) |
| installation du plugin `context-mode` | supprimée — le shellMinimizer d'OMP + le déversement en artefact couvrent le besoin |

## Installation

```sh
omp plugin install token-diet@omp-dev-team
bash plugins/token-diet/install.sh    # puis redémarrez omp
```

L'installeur : installe/met à jour ctx-wire et ses shims PATH, fusionne les
quatre filtres dans `~/.config/ctx-wire/filters.toml`, installe `ast-grep`,
fusionne `config.snippet.yml` clé de premier niveau par clé, et recopie
`extensions/` + `rules/` dans `~/.omp/agent`. Options : `--no-update`,
`--no-config`, `--no-cleanup`, `--insecure-tls`, `--ca-file=…`.

## Comment c'est câblé dans OMP

- **ctx-wire** → `ctx-wire shims install` dépose des wrappers transparents dans
  `~/.local/bin` (en tête du PATH, hérité par l'outil bash d'OMP) : l'agent lance
  les commandes **sans préfixe** et leur sortie est filtrée avant d'atteindre le
  contexte. Les logs complets restent sur disque ; `ctx-wire gain` montre les
  économies, `ctx-wire doctor` vérifie. **Redémarrage requis** : un process OMP
  déjà lancé quand l'installeur s'exécute garde son ancien PATH ; l'installeur
  sonde un shell de login frais et prévient si la session est obsolète.
  (`path-inject` comble le même trou depuis l'intérieur du process pour les
  sessions suivantes.)
- **Filtres** → uniquement `dotnet publish`/`pack`/`run`/`tool`. `git` et
  `dotnet build|test|restore|format` sont traités par le minimizer Rust d'OMP,
  actif par défaut : livrer les nôtres ferait deux passes sur les mêmes octets.
  **Le trou de locale est la vraie raison d'être de ce pack** : le durcissement
  `LANG=C.UTF-8` d'OMP est **Windows uniquement**, donc sous Linux/macOS une
  locale française atteint git/dotnet et les filtres anglais natifs manquent en
  silence. Le correctif le moins cher est d'épingler la locale
  (`DOTNET_CLI_UI_LANGUAGE=en`, `LC_MESSAGES=C`) — voir `ctx-wire/README.md`.
  Pas de roumain : git et .NET ne livrent aucune traduction `ro`.
- **Extensions** → recopiées dans `~/.omp/agent/extensions/token-diet`, car OMP
  ne charge pas les points d'entrée d'extension depuis un install marketplace.
  `path-inject` est toujours actif et sans configuration. `context-compress` est
  **désactivé** sauf si vous posez `TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full` :
  en `safe` tout son travail (strip ANSI, collapse des espaces) est déjà fait à
  la source, et sa fenêtre `keepRecent` **glisse** — à chaque tour un message de
  plus bascule d'intact à compressé, soit un changement d'octets récurrent dans
  le préfixe déjà envoyé, exactement ce qui casse le cache de prompt. Ne
  l'activez qu'après avoir mesuré votre taux de lecture cache. La logique pure
  vit dans `extensions/lib` et est testée par `bun scripts/extensions.test.ts`.
- **règle token-tools** → `rules/token-tools.md` est `alwaysApply: true`, donc
  présente dans le prompt système de **chaque** requête : elle fait
  délibérément ~15 lignes. Le provider de règles plugin d'OMP ne découvre
  `rules/*.md` qu'à l'intérieur de racines de packages d'extension *configurées*,
  et un install marketplace n'en est pas une — les installeurs la recopient donc
  dans `~/.omp/agent/rules/token-diet-*.md`, que le provider natif (priorité 100)
  scanne toujours.
- **config.snippet.yml** → fusionné clé de premier niveau par clé via
  `scripts/lib/cfg.sh`, pour que lancer l'installeur racine puis celui-ci ne
  puisse pas produire de clés YAML dupliquées. Il pose `secrets.enabled`,
  `tools.artifactSpillThreshold: 10`, `bashInterceptor.enabled`,
  `shellMinimizer.sourceOutlineLevel: aggressive`, `compaction.idleEnabled`,
  `read.summarize.prose`, les bascules skills/commands, et `disabledProviders`
  (`~/.claude/plugins`, `~/.codex`, `~/.gemini`, `~/.cursor`,
  `~/.codeium/windsurf`, `~/.config/opencode`, `.clinerules`). Le provider
  `github` reste délibérément actif pour que copilot-preset continue de marcher.
- **Visibilité coût / cache** → natif, sans plugin :
  ```yaml
  statusLine:
    preset: custom
    rightSegments: [cost, cache_hit, cache_write, context_pct, usage]
  ```
- **À noter côté fichier de contexte** → sans `~/.omp/agent/AGENTS.md`, OMP se
  rabat sur le `CLAUDE.md` utilisateur de Claude Code et le lit verbatim, y
  compris les conseils
  propres à Claude Code (p. ex. un bloc injecté par ctx-wire disant de préférer
  le shell brut aux outils natifs — juste pour Claude Code, faux pour OMP). Les
  installeurs affichent un avertissement ponctuel dans ce cas.

## Notes

- Se marie naturellement avec **copilot-preset** (modèles peu chers au token) —
  moins de tokens × tokens moins chers.
- Ne livre aucun serveur MCP ni LSP. La navigation et les sémantiques C# passent
  par l'outil `lsp` natif d'OMP, qui a `omnisharp` en défaut intégré pour
  `.cs`/`.csx`.
- Indépendant des autres plugins ; n'installez que ce que vous voulez.
- La CI lance les deux preuves : `python3 ctx-wire/scripts/verify-filters.py ctx-wire/filters.d`
  (23/23) et `bun scripts/extensions.test.ts`.
