# Review — omp-dev-team

Revue complète du dépôt (6 plugins), menée contre deux sources amont clonées et
lues, pas contre des notes de version :

- `bdfinst/agentic-dev-team` **v10.20.0** (HEAD `37aa6a5`, 2026-07-26)
- `can1357/oh-my-pi` **17.1.4**

> **La version précédente de ce fichier est périmée et a été remplacée.** Elle
> affirmait 32 agents, ~79 skills, 8 extensions, 106 clés d'index mortes et
> 9 agents fantômes — tout cela était déjà faux au moment de la relire. Onze de
> ses constats étaient corrigés dans l'arbre. Un document de revue qui décrit le
> dépôt moins fidèlement que le dépôt lui-même est exactement le défaut que cette
> passe existe pour attraper, d'où sa réécriture plutôt que sa mise à jour.

## Vérifié sur cette machine

| Vérification | Résultat |
|---|---|
| `tsc --noEmit` contre les types publiés d'OMP 17.1.4 | ✅ 0 erreur |
| `bun build` de toutes les extensions (tous plugins) | ✅ 0 erreur |
| `bun` tests dev-team + token-diet | ✅ tous passent |
| `verify-filters.py` (ctx-wire) | ✅ 23/23 |
| `shellcheck --severity=warning` + `bash -n` | ✅ propre |
| `ci-framework-compliance.mjs` (checks A→N) | ✅ 0 violation |
| générateurs registres + index `--check` | ✅ à jour |
| merge de config (global puis par plugin) | ✅ aucune clé YAML dupliquée |
| `install.ps1` | ⚠️ non vérifiable ici (pas de `pwsh`) — le CI le parse |

## Ce que la passe a changé, et pourquoi

### 1. 60 % de la grille de modèles était inerte

`model-resolver.ts:946` : seuls `smol`, `slow` et `designer` héritent de
`default`. Sans `modelRoles.plan`, la résolution **retombe silencieusement sur le
modèle de session** — et 18 de nos agents déclaraient `pi/plan`. Pire, `@task` est
*délibérément* session-héritant (`:936-943`), donc les 5 agents du « tier code pas
cher » ne l'étaient pas non plus.

Corrigé : `plan` et `task` posés explicitement, chaque agent porte une **liste de
rôles** terminée par `@default` (OMP prend le premier motif résoluble, donc un
agent route même sans le snippet de config), et le préfixe legacy `pi/` passe à la
forme canonique `@`.

Rôles auparavant morts et désormais câblés : `designer` (UI/UX + a11y), `vision`
(obligatoire — `inspect_image` échoue en dur sur un modèle texte seul) et
`advisor` (volontairement d'un autre fournisseur que `slow`).

### 2. Le résolveur de bandes d'effort dupliquait ce que le harness fait déjà

L'ADT amont a supprimé la machinerie équivalente (ADR-0026) : *« Zéro code du
plugin ne se tient entre le frontmatter d'un agent et le modèle que le harness
exécute réellement. »* Trois défauts propres à notre version ont confirmé le
retrait : elle branchait sur les chaînes littérales `"opus"`/`"sonnet"` — une
dépendance à des noms Anthropic **dans un portage ouvert sur les fournisseurs** ;
un hook lisait l'état de l'orchestrateur (`plan-gate.json`), ce qu'ADR-0019
interdit ; et elle était activée par défaut sans gain mesuré, ce qu'ADR-0022
interdit. Supprimée, remplacée par la résolution native + l'`effort` par appel de
l'outil `task`.

### 3. Le réglage vedette de token-diet n'existe plus

`tools.discoveryMode` et `tools.essentialOverride` ont été **supprimés dans OMP
17.0.0** et sont désormais effacés de la config au chargement
(`config/settings.ts`). C'était l'argument de vente n°1 du plugin (« ~29K → ~20K,
−31 % »), répété dans 9 fichiers, et `install.sh` les écrivait dans la config
globale de chaque utilisateur. Le remplaçant, `tools.xdev`, ne demande aucune
configuration.

Plus largement, OMP 17 a absorbé la couche runtime du plugin :
`compaction.supersedeReads` (défaut `true`) remplace read-dedup et context-dedup ;
les segments natifs coût/cache de la statusline remplacent cache-meter ;
`secrets.enabled` remplace le « scrub » in-process qui, vérification faite, ne
redactait rien. Le plugin est donc réduit à ce qu'OMP ne fait pas : des filtres
ctx-wire *sémantiques* (OMP tronque mécaniquement : 50 Ko de queue, colonnes à
768 octets) et le skill `caveman`, qui vise les tokens de **sortie**.

### 4. Bugs réels trouvés par le typecheck

`bun build` empaquette et **efface les types** : une erreur de type compile
proprement. L'ajout de `tsc --noEmit` contre les vrais types publiés d'OMP a
immédiatement révélé :

- **15 sites** appelant `ctx.ui.notify(msg, "warn")` alors que l'API prend
  `"info" | "warning" | "error"` — toutes les notifications de garde portaient une
  sévérité invalide, dans 9 fichiers d'extension ;
- le handler de commande d'`impl-verify` retournait des chaînes qu'OMP jette (le
  contrat est `Promise<void>`) ;
- `azure-devops-fs` passait `signal` à `execFileSync`, qui n'a pas cette option —
  l'annulation n'atteignait donc jamais le sous-processus `az`.

### 5. Les installeurs

- `${YES:+-y}` s'expansait **toujours** (`YES=0` est une chaîne non vide) : chaque
  installeur de plugin recevait `-y` à chaque exécution, sautant silencieusement
  tous les prompts de credentials. `install.ps1` faisait correctement — d'où une
  divergence de comportement Unix/Windows.
- `ask()` était défini ~50 lignes **après** le bloc TLS qui l'appelle.
- `local name="$1" dest=".../$name"` : `local` développe tous ses arguments avant
  la moindre affectation, donc `$name` lisait la portée externe. Ça ne marchait
  que parce que l'appelant utilisait le même nom de variable.
- Chaque installeur de plugin greppait **sa propre** bannière puis réappendait son
  snippet entier : la séquence recommandée par le README produisait des clés
  YAML top-level dupliquées, que les parseurs résolvent en last-wins — l'inverse
  de la garantie affichée. `scripts/lib/cfg.sh` merge désormais clé par clé.

### 6. Le préchargement de skills coûtait plus qu'il ne rapportait

Le portage du mécanisme `skills:` amont vers `autoload-skills:` d'OMP injecte les
corps **en entier** avant le premier tour. Mesuré : qa-engineer ~25K tokens,
software-engineer ~16K, architect ~12,5K, à **chaque** dispatch. Listes ramenées
aux skills réellement ouverts à chaque run (~41K tokens économisés par cycle
complet) ; le reste reste à un `/skill:<name>` près.

## Décisions d'arbitrage

| Sujet | Décision |
|---|---|
| Tier `task` sur Copilot | MAI-Code-1-Flash reste **primaire**. Kimi K2.7 (seul open-weight du catalogue Copilot) livré en **option commentée** : sortie moins chère mais `maxTokens` 32K contre 128K, sur le tier *build*, et désactivé par défaut sur les tenants Business/Enterprise. |
| Serena / Roslyn | **Coupé.** OMP expose un outil `lsp` natif (definition/references/symbols/hover/rename/code_actions) et détecte `omnisharp` seul. 3 skills, 1 extension, une entrée `.mcp.json` et une dépendance d'install uvx + .NET 10 en moins. `serena-build-net.ts` reste : rien de natif ne bloque la fin de session sur un build rouge. |
| Atlassian / Context7 | **Repassés sur leurs MCP officiels** (`mcp.atlassian.com/v1/mcp/authv2` en OAuth 2.1, `mcp.context7.com/mcp`). Les enrobages CLI existaient au motif que les schémas MCP entrent dans chaque system prompt ; `tools.xdev` a rendu l'argument caduc. |
| `yagni` | Supprimé. |
| `enabledModels: [github-copilot/*]` | **Commenté.** Un tableau est remplacé en bloc par toute couche supérieure, un motif sans correspondance donne une liste de modèles **vide sans repli**, et cela ferme la porte aux fournisseurs open-weight qu'OMP sert déjà nativement. |
| `effort: high` uniforme (amont) | **Non adopté.** ADR-0026 le qualifie lui-même de remise à zéro non calibrée. Notre `thinking-level:` par agent est l'artefact mieux calibré. |
| `color:` / `memory:` (ADR-0027/0028 amont) | **Non portables.** Inertes dans OMP — sa doc indique que le pipeline mémoire est ignoré pour les sous-agents. Le check M du CI échoue si l'un d'eux réapparaît. |

## Reste ouvert

Suivi dans `docs/upstream-v8-v10.md` § « Still open » : portage de `/ship`,
réconciliation des skills `build` (290 lignes de diff) et `plan` (259, dans les
deux sens), `co-evolution-audit`, `test-audit-disable`, `agent-readiness`,
les reviewers de réactivité React/Vue/Angular, et un `omp-setup-review`.

Deux points de posture non résolus, honnêtement documentés plutôt que corrigés :
les gardes restent **consultatives** (leur couverture `bash` repose sur des regex,
pas sur un parse shell — `bash -c`, heredocs et `python -c` passent), et rien ne
prouve à l'exécution que les 12 extensions ont bien enregistré leurs handlers.
L'amont a rencontré exactement ce mode de panne : sa couche PreToolUse est restée
**inerte pendant des mois** sans que personne ne le remarque.

---

*Le CI applique désormais ces constats : `ci-framework-compliance.mjs` (checks
A→N) échoue sur une référence `skill://` morte, un chemin `plugins/...` inexistant,
une collision avec une commande native d'OMP, un `${CLAUDE_PLUGIN_ROOT}` en prose,
une clé de frontmatter qu'OMP ignore, un réglage supprimé, ou un compteur de
README qui ment.*
