# Spike : caveman-code vs token-diet

> Branche `claude/happy-darwin-4h2oho`. Note de comparaison/décision — *« on verra
> ce qu'on en fait »*. Aucune modif de comportement de token-diet n'est faite ici :
> ce fichier est inerte (recherche), pas chargé par OMP ni par l'installeur.

Repo étudié : <https://github.com/JuliusBrussee/caveman-code> (Julius Brussee, MIT).

## TL;DR

- **caveman-code n'est pas un plugin : c'est un agent complet, fork frère de Pi.**
  OMP est *« a fork of pi-mono by Mario Zechner »* ; caveman-code est *« a heavy
  fork of pi-code by Mario Zechner »*. Les deux vivent **dans la même couche**
  (l'agent), pas l'un au-dessus de l'autre. On n'« installe » pas un agent
  concurrent comme plugin dans OMP.
- **Ça ne remplace pas token-diet.** La partie « token » de caveman-code (sa
  *Caveman Mode*) est un **sous-ensemble** de ce que token-diet fait déjà — et sur
  le point qui compte pour nous (multilingue), token-diet est **devant** :
  caveman-code s'appuie sur **RTK**, que token-diet a justement **évalué puis
  abandonné** (anglais-only) au profit de ctx-wire + context-mode.
- **La seule vraie idée à prendre = le *read-dedup*** (stub sur relecture d'un
  fichier inchangé). C'est le seul mécanisme de caveman-code que ni OMP ni
  token-diet ne couvrent. Portage proposé plus bas via une extension OMP.
- **Reco : garder token-diet tel quel ;** éventuellement lui ajouter une petite
  extension `read-dedup` (autonome, complémentaire de la compaction). Ne pas
  intégrer caveman-code en tant que tel. Surveiller son upstream pour les idées.

## 1. Ce qu'est réellement caveman-code

| | |
|---|---|
| Nature | Agent de codage terminal **complet** (TUI + CLI), pas une extension |
| Origine | *« heavy fork of pi-code by Mario Zechner »* (badlogic) |
| Code | Monorepo TypeScript, **9 packages** : `agent`, `ai`, `coding-agent`, `markdown-preview`, `mom`, `pods`, `sdk`, `tui`, `web-ui` |
| Install | `npm i -g @juliusbrussee/caveman-code` → binaire `caveman` |
| Argument | *« talks like a caveman — and burns half the tokens »*, ~2× moins de tokens que Codex |

L'auteur lui-même distingue ses deux repos :

> *« This skill shrink what agent **say**. **caveman-code** shrink **everything**. »*

- `JuliusBrussee/caveman` = **la skill** terse-output (ce qu'on a déjà porté).
- `JuliusBrussee/caveman-code` = **l'agent entier** (ce repo).

### La « Caveman Mode » = 4 couches de compression

| Couche | Cible | Mécanisme | Couvert par token-diet ? |
|---|---|---|---|
| **Caveman Mode** | réponse du modèle | fragments terses, niveaux `lite`/`full`/`ultra` | ✅ **déjà** = skill `/caveman` (lite/full/ultra) |
| **Tool Budgets** | sortie d'outil | caps par outil (bash 80 / read 300 / grep 120 lignes) + strip ANSI + collapse lignes vides | ⚠️ **équivalent supérieur** = ctx-wire (filtres sémantiques) + context-mode (index FTS5/BM25), pas des caps aveugles |
| **Read Dedup** | relectures | fichier *fingerprinté* par session ; relecture inchangée → **stub** (−99 % sur les répétitions) | ❌ **manque réel** (ni OMP ni token-diet) |
| **RTK** (Rust Token Killer) | sortie bash | binaire Rust externe **optionnel**, −60 % à −90 % | ✅ **déjà évalué et abandonné** (anglais-only) |

Chiffres annoncés : **−86 %** agrégé sur 10 fixtures de sortie d'outil ; session
15 tours ≈ **+567K tokens économisés (~1,70 $ Sonnet)**.

### Le reste de caveman-code = des features d'**agent**, pas de token

Goal loop (autopilot « Ralph »), plan mode, sous-agents (≤7 worktrees),
**architect/editor split** (~3–5× moins cher), session branching/checkpoints/`/tree`,
**cavemem** (mémoire persistante BM25 + vecteurs locaux), MCP, 20+ providers.

→ Ce sont des capacités du **runtime de l'agent**. OMP a déjà ses équivalents
(plan mode natif, sous-agents `task`/worktrees, tiers `modelRoles` +
copilot-preset pour le split lent/rapide, compaction/handoffs, MCP). Rien de tout
ça n'est « plugin-able » : ça vit dans le fork, comme chez OMP.

## 2. « On peut l'intégrer dans un plugin ? » — la lignée Pi commune

La prémisse est juste : **OMP et caveman-code descendent tous deux du Pi de Mario
Zechner** (pi-mono / pi-code). Mais « partir du même Pi » ne veut pas dire
« caveman-code = un plugin OMP ». Ça veut dire qu'ils sont **frères**, pas
parent/enfant. Conséquences concrètes :

1. **Wholesale, non.** Installer caveman-code « comme plugin » reviendrait à faire
   tourner un second agent dans le premier. Hors sujet : « remplacer token-diet
   par caveman-code » = « remplacer OMP par caveman-code ».
2. **Au niveau code, oui — mais c'est patcher OMP, pas livrer un plugin.** La
   lignée commune rend un *cherry-pick* d'une feature entre forks **plus faisable**
   que depuis un outil random (mêmes formats de tool/hook/skill côté Pi). Mais ça
   modifie OMP lui-même → ça part chez `can1357/oh-my-pi`, pas dans notre
   marketplace.
3. **Au niveau idée, oui, et c'est la bonne voie.** OMP expose une vraie API
   d'extension — *« An extension is a TypeScript module »* — `ExtensionAPI` de
   `@oh-my-pi/pi-coding-agent` : `registerCommand` (slash-commands),
   `pi.on("session_start" | "turn_end" | "tool_result", …)`, et un gating
   pré-outil qui renvoie `{ block, reason }` (cf. `dev-team/extensions/*.ts`).
   C'est **exactement** par là que `context-mode` réécrit la sortie d'outil. Donc
   une *idée* de caveman-code (ex. read-dedup) se ré-implémente proprement en
   extension de plugin.

**La couche « say » est déjà passée par la voie 3 :** notre skill `/caveman`
(`skills/caveman/SKILL.md`) est le portage natif OMP de `JuliusBrussee/caveman`.

## 3. « Ça remplace token-diet ? » — Non

Mis face à face, caveman-code couvre **un sous-ensemble** de la stratégie de
token-diet, et token-diet ajoute beaucoup que caveman-code n'a pas :

| Levier token | caveman-code | token-diet | Verdict |
|---|---|---|---|
| Sortie modèle terse | Caveman Mode | skill `/caveman` (lite/full/ultra) | **égalité** (même source) |
| Sortie d'outil compressée | caps aveugles + RTK | ctx-wire (filtres sémantiques, secret-scrub) + context-mode (index FTS5/BM25) | **token-diet >** (sémantique, pas troncature) |
| Multilingue (FR/RO) | ❌ RTK anglais-only | ✅ filtres EN+FR + context-mode language-agnostic | **token-diet >** (critique pour nous) |
| Relecture dédupliquée | ✅ read-dedup | ❌ | **caveman-code >** (seul manque) |
| Graphe symboles/appels | ❌ | ✅ CodeGraph (MCP) | **token-diet** |
| Docs de libs à jour | ❌ | ✅ context7 | **token-diet** |
| Écrire moins de code | ❌ | ✅ skill `/yagni` | **token-diet** |
| Surface d'outils légère | ❌ | ✅ `discoveryMode: all` (~18K→~10K) | **token-diet** |
| Isolation des providers | ❌ | ✅ exclut ~/.claude, ~/.codex, … | **token-diet** |

Point saillant : **token-diet a déjà parcouru et dépassé le chemin de
caveman-code.** Le README l'écrit noir sur blanc — ctx-wire *« Replaces the
earlier RTK integration (RTK is also English-only, so it offered no localization
advantage) »*. Autrement dit : on a essayé le moteur de compression de
caveman-code (RTK), et on l'a retiré parce qu'il ne sait pas compacter du FR/RO.

## 4. Ce qui vaut la peine d'être pris : le **read-dedup**

Seul mécanisme de caveman-code absent chez nous. Il est **complémentaire** de la
compaction OMP (la compaction résume l'historique de façon *lossy* ; le dedup
empêche le doublon d'**entrer**, sans perte — la 1ʳᵉ lecture reste en contexte).
Gain annoncé −99 % sur les relectures.

### Proposition (esquisse, **non câblée**, à valider contre l'API OMP)

Extension OMP qui, par session, garde l'empreinte (mtime+taille ou hash) des
fichiers lus, et remplace une relecture inchangée par un stub. Deux points d'API
à **confirmer** contre `@oh-my-pi/pi-coding-agent` et l'implémentation de
`context-mode` avant prod (cf. `// TODO API`) : (a) la forme exacte pour
*remplacer* le résultat d'un `read`, (b) l'accès au contenu/chemin dans le hook.

```ts
// plugins/token-diet/extensions/read-dedup.ts  (PROPOSITION — non livré)
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

export default function readDedup(pi: ExtensionAPI) {
  pi.setLabel("read-dedup");
  // empreinte par chemin, réinitialisée à chaque session
  const seen = new Map<string, string>();
  pi.on("session_start", async () => seen.clear());

  // Intercepte AVANT le read : si déjà lu et inchangé → stub au lieu des octets.
  // TODO API: confirmer le nom du hook pré-outil + la forme de retour qui
  // injecte `reason` comme résultat (cf. path-guard.ts -> { block, reason }).
  pi.onToolCall?.("read", async (event, ctx) => {
    const path = event.input?.path;
    if (!path) return;
    const fp = await fingerprint(ctx.cwd, path); // mtime+size, fallback hash
    if (seen.get(path) === fp) {
      return {
        block: true,
        reason: `[read-dedup] ${path} inchangé depuis sa 1ʳᵉ lecture cette ` +
                `session — réutilise la lecture précédente (octets non réinjectés).`,
      };
    }
    seen.set(path, fp);
  });
}
```

Caractéristiques : ~30 lignes, zéro dépendance externe (vs RTK = binaire Rust),
opt-in via `config.snippet.yml`, et s'aligne sur le style des extensions
existantes de `dev-team`. À tester sur un repo réel (relecture du même gros
fichier sur plusieurs tours) avant d'activer.

## 5. Recommandation

1. **Ne pas intégrer caveman-code** (agent concurrent, pas un plugin ; le
   remplacer à token-diet n'a pas de sens).
2. **Garder token-diet** : il couvre déjà la stratégie de caveman-code et la
   dépasse en multilingue, plus tout le reste (CodeGraph, context7, yagni,
   lean-tools, isolation).
3. **Option à valider ensemble : porter le read-dedup** en extension token-diet
   (le seul vrai manque). Petit, autonome, complémentaire de la compaction.
4. **Cosmétique optionnel** : la skill upstream `caveman` a aussi un niveau
   `wenyan` (chinois classique) que notre port n'a pas — anecdotique, à ignorer
   sauf demande.
5. **Veille** : surveiller l'upstream caveman-code (cavemem, goal loop) comme
   réservoir d'idées pour de *futurs plugins distincts*, pas pour token-diet.

## Sources

- caveman-code : <https://github.com/JuliusBrussee/caveman-code> (README, packages, CLAUDE.md)
- caveman (skill) : <https://github.com/JuliusBrussee/caveman>
- oh-my-pi : <https://github.com/can1357/oh-my-pi> (*« fork of pi-mono by Mario Zechner »*)
- pi-mono : <https://github.com/badlogic/pi-mono>
- token-diet : `plugins/token-diet/README.md`, `skills/caveman/SKILL.md`, `config.snippet.yml`
- API extension OMP : `plugins/dev-team/extensions/*.ts` (`ExtensionAPI`, `pi.on`, `registerCommand`, `{ block, reason }`)
</content>
</invoke>
