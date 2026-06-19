# caveman-code → token-diet : analyse & ce qu'on en a extrait

> Branche `claude/happy-darwin-4h2oho`. Étude de <https://github.com/JuliusBrussee/caveman-code>
> (Julius Brussee, MIT) et portage des bonnes idées dans token-diet, **à qualité
> constante**. Statut : **implémenté + testé** (voir §6). Mantra : le plus light
> possible en tokens, sans jamais perdre un détail technique.

## TL;DR

- **caveman-code n'est pas un plugin : c'est un agent complet, fork frère de Pi.**
  OMP est *« a fork of pi-mono by Mario Zechner »* ; caveman-code est *« a heavy
  fork of pi-code by Mario Zechner »*. Même couche, pas l'un au-dessus de l'autre
  → on **n'intègre pas** caveman-code « comme plugin », on **ré-implémente ses
  idées** via l'API d'extension OMP.
- **Ça ne remplace pas token-diet.** Sa « Caveman Mode » est un sous-ensemble de
  ce que fait token-diet, et sur le multilingue token-diet est devant (caveman-code
  s'appuie sur RTK, que token-diet a déjà abandonné car anglais-only).
- **Ce qu'on a pris** (3 extensions OMP natives, logique pure testée) :
  - `read-dedup` — **sans perte, actif** : relecture byte-identique d'un fichier
    inchangé → stub (port de la couche « Read Dedup »).
  - `context-dedup` — **sans perte, actif** : fusionne les blocs byte-identiques
    répétés dans le contexte avant chaque appel (toutes sources : `cat`, MCP…).
  - `context-compress` — **lossy, opt-in** : la version *qualité-préservée* du
    transform LLMLingua/Provence (voir §5), via un **protect mask**.
- **Ce qu'on a écarté** : RTK (anglais-only), le binding ONNX/BERT de LLMLingua
  (lourd, latence ×N agents), et la réécriture du **prompt user littéral** (hook
  `input`) — trop risqué pour la qualité.

## 1. Ce qu'est réellement caveman-code

Agent terminal complet (TUI+CLI), monorepo TypeScript **9 packages** : `coding-agent`
(sessions, extensions, skills, slash commands, subagents), `agent` (runtime :
tool-calling, loop, **compression/**), `ai` (API LLM unifiée), `tui`, `sdk`,
`markdown-preview`, + `web-ui`/`mom`/`pods` (hors scope v2). Install
`npm i -g @juliusbrussee/caveman-code`. L'auteur distingue ses deux repos :

> *« This skill shrink what agent **say**. **caveman-code** shrink **everything**. »*

- `JuliusBrussee/caveman` = **la skill** terse-output → déjà portée (`/caveman`).
- `JuliusBrussee/caveman-code` = **l'agent entier** (ce repo).

### La « Caveman Mode » = 4 couches

| Couche | Cible | Mécanisme (vérifié dans le code) | Côté token-diet |
|---|---|---|---|
| Caveman Mode | réponse modèle | fragments, niveaux lite/full/ultra | ✅ skill `/caveman` |
| Tool Budgets | sortie d'outil | caps bash 80 / read 300 / grep 120, strip ANSI, collapse | ⚠️ couvert mieux par ctx-wire (filtres sémantiques) + context-mode (index) que par des caps aveugles |
| **Read Dedup** | relectures | fichier *fingerprinté* par session, relecture → stub (−99 % sur répétitions) | ❌→ **porté** (`read-dedup`) |
| RTK | sortie bash | binaire Rust externe optionnel, −60..−90 % | ✅ déjà évalué et **abandonné** (anglais-only) |

### Le sous-système `agent/src/compression/` (le cœur « shrink everything »)

C'est un **pipeline de middlewares** (fichiers réels) :

- `types.ts` — `CompressionMiddleware { name, compress(block, opts) }` ;
  `CompressionOptions { targetRatio 0..1, activationThreshold }` ;
  `CompressionResult { bytes, estimatedInput/OutputTokens, compressed, via }` ;
  reranker `{ chunks, query, keepRatio, dropBelow } → { kept[{chunk,score}], dropped }` ;
  `estimateTokens` ≈ 1 token / 4 chars.
- `llmlingua.ts` — **LLMLingua-2** : classification de tokens **BERT via ONNX**
  (`useOnnx=true`), garde le top-N par proba :
  `keepCount = max(1, floor(contentTokens.length * targetRatio))`. **Aucune
  protection** code/chemins/termes techniques (constat verbatim : *« no
  force-preserve logic for code syntax, technical terms, or semantic anchors »*).
- `provence.ts` — reranker style Provence : *prune* des chunks sous un score
  (compression de contexte par pertinence à une requête).
- `fallback.ts` — `safeCompress(attempt, passthrough, middleware)` : **passthrough
  en cas d'erreur** (ne casse jamais la requête). + `model-download.ts` (télécharge
  le modèle BERT), `bert-tokenizer.ts`.

## 2. « Cavemaniser le prompt utilisateur » — ce que c'est vraiment

Dans `agent/src/agent-loop.ts`, la compression n'est pas appelée par tour à la
main : il y a `config.transformContext` — *« Apply context transform if configured
(AgentMessage[] → AgentMessage[]) »*. **C'est ça** « rendre l'entrée plus
caveman » : un transform sur **tout le tableau de messages** (historique + prompt)
avant chaque appel modèle, où sont branchés LLMLingua/Provence. C'est l'**entrée**
qu'on compresse, pas seulement la sortie.

**Équivalents OMP** (vérifiés dans `coding-agent/src/extensibility/shared-events.ts`
+ `extensions/types.ts`) — un plugin peut s'abonner à :
- **`context`** → *« messages about to be sent to the LLM (deep copy, safe to
  modify) »* = l'analogue exact de `transformContext`. ✅ c'est notre vecteur.
- `tool_call` → `{ block, reason }` (gate pré-outil) ; `tool_result` → peut
  modifier le résultat ; **`input`** → peut *remplacer le texte/les images de
  l'utilisateur*. ⚠️ `input` = littéralement « réécrire le prompt user » — **on
  l'évite** : compresser les instructions de l'utilisateur est le moyen le plus
  sûr de corrompre l'intention. On compresse le **contexte**, jamais l'ordre humain.

## 3. « On peut l'intégrer comme plugin ? » — la lignée Pi commune

Prémisse correcte (même Pi), mais frères ≠ parent/enfant :
1. **En bloc : non** (faire tourner un agent concurrent dans OMP).
2. **Au niveau code : possible mais c'est patcher OMP**, pas livrer un plugin
   (irait chez `can1357/oh-my-pi`).
3. **Au niveau idée : oui** via l'API d'extension (`registerCommand`, `pi.on(...)`).
   C'est la voie qu'on a prise (comme `context-mode` le fait déjà).

## 4. « Ça remplace token-diet ? » — Non

| Levier token | caveman-code | token-diet |
|---|---|---|
| Sortie modèle terse | Caveman Mode | ✅ `/caveman` (même source) |
| Sortie d'outil | caps aveugles + RTK | ✅ ctx-wire (sémantique) + context-mode (index) |
| **Multilingue FR/RO** | ❌ RTK anglais-only | ✅ filtres EN+FR + language-agnostic |
| Relecture/contexte dédupliqués | ✅ read-dedup | ✅ **read-dedup + context-dedup** (porté) |
| Compression d'entrée (prompt/contexte) | LLMLingua/Provence (lossy, sans garde-fou) | ✅ **context-compress** protect-maskée (opt-in) |
| CodeGraph / context7 / yagni / lean-tools / isolation | ❌ | ✅ |

token-diet a **déjà parcouru et dépassé** le chemin de caveman-code (RTK retiré
car non localisable), et lui ajoute beaucoup. Conclusion inchangée : **on garde
token-diet**, on lui ajoute les bonnes idées.

## 5. Améliorer LLMLingua/Provence pour **préserver les détails importants**

Oui — et c'est précisément le défaut de l'intégration de caveman-code (compression
uniforme, zéro force-preserve). Deux leviers, qu'on combine :

**(a) Protect mask (notre implémentation, déterministe, sans modèle).** Avant toute
compression, on *masque* les empans à haute valeur — bloc de code ```` ``` ````,
code inline `` `…` ``, URLs, chemins, hash/sha, **nombres**, identifiants qualifiés
(`a.b.c`, `ns::x`, kebab-case), `CONSTANTES`, flags `--xxx` — en placeholders
inertes ; on ne compresse que la **prose** entre eux ; on **restaure byte à byte**.
Biais volontaire : dans le doute, on **protège** (on compresse moins) plutôt que de
risquer une perte. C'est `extensions/lib/protect.ts`, couvert par des tests qui
vérifient la préservation exacte (§6).

**(b) Le même masque alimente un vrai LLMLingua-2** (si un jour on veut le tier
agressif). LLMLingua-2 expose exactement les bons paramètres
([microsoft/LLMLingua](https://github.com/microsoft/LLMLingua/blob/main/DOCUMENT.md)) :
- `force_tokens` ← **la liste des empans protégés** (jamais droppés) ;
- `force_reserve_digit=True` ← préserve tous les tokens contenant des chiffres ;
- `drop_consecutive=True` ← nettoie les force-tokens consécutifs.
Et côté **Provence** (sentence-level) : ne jamais *pruner* une phrase contenant un
empan protégé (code, identifiant, nombre) → on garde les phrases porteuses de
détail même à fort taux de coupe.

Autrement dit : la couche `protect` est **la** brique qui rend la compression
d'entrée sûre, qu'elle soit déterministe (notre défaut) ou ML (escalade future).

## 6. Ce qu'on a livré (implémenté + testé)

```
plugins/token-diet/
  extensions/
    read-dedup.ts        tool_call gate ; LOSSLESS ; ON (TOKEN_DIET_READ_DEDUP=0 pour couper)
    context-dedup.ts     hook context ; LOSSLESS ; ON (TOKEN_DIET_CONTEXT_DEDUP=0)
    context-compress.ts  hook context ; LOSSY ; OPT-IN (TOKEN_DIET_CONTEXT_COMPRESS=safe|lite|full)
    lib/protect.ts       protect/restore + compressProse + compress (PUR, testé)
    lib/messages.ts      collapseDuplicateBlobs + compressOldMessages (PUR, testé)
  scripts/extensions.test.ts   47 assertions — `bun plugins/token-diet/scripts/extensions.test.ts`
```

Garde-fous qualité (tous testés) :
- **read-dedup** : signature = `JSON(input) + (taille:mtime)` → une autre tranche
  (offset/limit) ou un fichier édité n'est **jamais** dédupliqué ; reset sur
  `session_compact`/`auto_compaction_end` (la compaction peut évincer la 1ʳᵉ
  lecture) → on ne cache jamais un contenu absent du contexte.
- **context-dedup** : ne touche que `assistant`/`tool`, garde la **dernière** copie
  verbatim (la canonique est dans le même payload → sans perte), seuil
  `TOKEN_DIET_DEDUP_MIN_CHARS` (1200).
- **context-compress** : protect mask + **fenêtre de récence** intacte
  (`KEEP_RECENT`, défaut 6) + **jamais** `user`/`system` + `activationThreshold`
  (`MIN_CHARS`, 600) + garantie **never-expand** + `try/catch` passthrough.
- OMP passe au hook `context` une **deep copy** → la session sauvegardée n'est
  jamais altérée, même en cas de bug.

### Différé volontairement (qualité / coût)
- **Binding ONNX/BERT de LLMLingua-2 + Provence** : nécessite un download de modèle
  + inférence locale **avant chaque appel** (×32 agents dev-team) = latence et
  dépendance lourde. La voie est documentée en §5 et **réutilise notre protect
  mask** ; à activer derrière un flag explicite si on en a besoin.
- **Réécriture du prompt user** (hook `input`) : risque qualité inacceptable.
- **Caps aveugles de sortie d'outil** : ctx-wire/context-mode font mieux.

## 7. Recommandation

1. **Garder token-diet** ; **ne pas intégrer caveman-code** en tant que tel.
2. **Activer par défaut** read-dedup + context-dedup (sans perte). Déjà le cas.
3. **context-compress** reste **opt-in** (lossy) — l'essayer d'abord en `safe`
   (quasi sans perte : ANSI/espaces/lignes vides), puis `lite`/`full` si le gain
   le justifie, en surveillant la qualité.
4. **Veille** : cavemem (mémoire), goal loop — réservoir d'idées pour de *futurs*
   plugins distincts, pas pour token-diet.

## Sources

- caveman-code : <https://github.com/JuliusBrussee/caveman-code> (README, CLAUDE.md,
  `packages/agent/src/compression/{types,llmlingua,provence,fallback}.ts`,
  `agent-loop.ts`, `packages/coding-agent/src/modes`)
- caveman (skill) : <https://github.com/JuliusBrussee/caveman>
- oh-my-pi : <https://github.com/can1357/oh-my-pi> — `extensibility/shared-events.ts`,
  `extensibility/extensions/types.ts` (events `context`/`tool_call`/`tool_result`/`input`)
- pi-mono : <https://github.com/badlogic/pi-mono>
- LLMLingua-2 : <https://github.com/microsoft/LLMLingua/blob/main/DOCUMENT.md> ·
  papier <https://arxiv.org/pdf/2403.12968> (`force_tokens`, `force_reserve_digit`,
  `drop_consecutive`)
- token-diet : `README.md`, `skills/{caveman,token-diet}/SKILL.md`, `config.snippet.yml`,
  `extensions/`, `scripts/extensions.test.ts`
