# dotnet-minified → token-diet : étude « adapter de minification In/Out »

> Branche `claude/minification-adapter-study-uc6o7e`. Étude de
> <https://github.com/Smoower/dotnet-minified> (`Smoower.Minified`, suite de libs
> .NET pour réduire les tokens AI). Question posée : *« j'aime l'idée de minifier,
> mais ça serait plus pertinent en tant qu'adapter In/Out, sans toucher au code
> réel des repo »* — est-ce que (1) ça s'intègre à une extension OMP, (2) ça
> génère un gain réel en tokens, (3) ça ne se paie pas en effort modèle
> (raisonnement/qualité) ? Statut : **étude — recommandation négative pour
> l'adapter, alternative sûre proposée**. Même mantra que caveman-code : le plus
> light possible en tokens, sans jamais perdre un détail technique.

## TL;DR

- **`Smoower.Minified` n'est pas un minifieur, et pas un adapter.** C'est une
  **bibliothèque C# d'alias courts** (`ok1()`, `db.Users.nt().w(...).s(...).ok1()`),
  d'extension methods et de noms de domaine abrégés. La forme compacte **est** le
  code source qu'on *commit* : *« same .NET code · fewer tokens · no magic »*. Elle
  compile vers le même IL — mais **elle n'est pas réversible** : il n'existe pas de
  forme verbeuse à reconstituer, on écrit directement le dialecte compact.
- **Ça contredit frontalement la prémisse « adapter In/Out sans toucher au repo ».**
  Un adapter In/Out suppose un transform **bijectif** verbeux↔minifié : minifier ce
  que voit le modèle (In), ré-étendre sa sortie vers le code réel verbeux (Out).
  `Smoower.Minified` ne fournit **aucun moteur réversible** — son « minified » est
  écrit à la main et le verbeux est *perdu* à la compilation. On ne peut donc pas
  *wrapper* le projet ; au mieux on **ré-implémente l'idée** (comme pour caveman-code),
  et l'idée se heurte à trois murs (réversibilité, surface d'édition, qualité).
- **Vecteur d'intégration OMP : il existe** (mêmes hooks que token-diet : `context`,
  `tool_result` sur `read` pour le In, `tool_call` sur `write`/`edit` pour le Out) —
  **mais le Out est un piège.** OMP édite les **octets réels du fichier** (`edit` =
  remplacement de chaîne ; `read-dedup` clé sur `taille:mtime`). Si le modèle voit du
  minifié et que le disque est verbeux, chaque `old_string` d'édition rate sa cible,
  les diffs/numéros de ligne/grep divergent. Maintenir deux représentations
  synchronisées d'un même fichier casse l'outillage d'édition.
- **Gain token réel : étroit et largement déjà capté.** Les chiffres annoncés
  (≈ 38 % de tokens *output* sur un controller, 10–25 % sur un projet) supposent
  qu'on **adopte la lib comme style de code** — pas qu'on l'applique en adapter.
  En adapter sur du code, le seul levier *sans perte* est le whitespace, que
  `context-compress` (niveau `safe`) **strippe déjà**. Le gros levier (renommage
  d'identifiants/alias) est précisément ce que `protect.ts` **protège byte-identique
  exprès**, parce que c'est le plus sûr moyen de casser la correction.
- **Effort modèle : oui, ça se paie.** Les alias `ok1()`/`nt()`/`w()`/`s()` sont
  **hors-distribution** : le modèle doit porter un dictionnaire d'alias en mémoire
  de travail et traduire → tokens de raisonnement + taux d'erreur ↑ + injection du
  dictionnaire en contexte (coût input). Le gain I/O sur le fil est repayé en
  *thinking* et en *retries*. C'est exactement la raison pour laquelle caveman-code.md
  a **écarté** la réécriture des empans de code.
- **Recommandation : ne pas construire l'adapter de minification.** Garder la ligne
  token-diet (compression *de contexte* sûre, jamais du code généré). Si on veut
  gratter des tokens *output* sur C#, le faire **en distribution** via une skill
  d'idiomes terses (cf. §7), pas via un dialecte d'alias réversible.

## 1. Ce qu'est réellement `Smoower.Minified`

Suite de libs C# (.NET 8/9/10) qui réduit les tokens quand un modèle **génère** du
code ASP.NET Core / EF Core. **Pas de minification au sens classique** (pas de
compilateur-plugin, pas d'AST transform, pas de regex) :

| Levier | Mécanisme | Exemple |
|---|---|---|
| Alias courts | helper/extension methods qui encapsulent un pattern | `ok1()` = `FirstOrDefaultAsync()` + `NotFound()`/`Ok()` |
| Chaînage abrégé | extension methods sur `IQueryable`/EF | `db.Users.nt().w(...).s(...)` |
| Noms mappés | identifiants verbeux → abréviations (tooling/analyzers) | niveau L2 |
| Whitespace packing | suppression d'espaces | niveau L3 |

Trois niveaux de compaction, lisibilité ↘ vs tokens ↘ : **L1** alias seuls
(réduction minime), **L2** noms mappés + outillage (~18 % sur l'API d'exemple),
**L3** packing maximal (~25 %). Échantillon « task-management » cité : `5049 → 3785`
tokens. Revendication : ≈ 38 % de tokens *output* sur un fichier controller.

**Deux propriétés structurantes pour notre question :**

1. **Ce n'est pas un transform, c'est une convention + un runtime.** Le « minified »
   est du C# valide écrit à la main qu'on *commit*. Il n'y a pas de source verbeuse
   en regard.
2. **Ce n'est pas réversible.** *« Not reversible… the full form is lost during
   compilation to IL. »* Il n'existe aucune fonction `expand(minified) → verbose`.

## 2. La prémisse « adapter In/Out » — pourquoi elle ne colle pas

L'idée de l'utilisateur (légitime, et c'est exactement le pattern token-diet) :

```
IN  : code réel verbeux du repo  --minify-->  vue compacte montrée au modèle
OUT : sortie compacte du modèle  --expand-->  code réel verbeux écrit au repo
                              (le repo reste verbeux, intact)
```

Cela **exige un transform bijectif** `verbose ⇄ minified`. Or `Smoower.Minified`
n'en est pas un : c'est un *style d'écriture* unidirectionnel et non réversible.
Conséquences :

- **On ne peut pas « brancher » le projet comme adapter.** Il ne fournit ni
  `minify(verbose)` ni `expand(minified)`. Réutiliser le projet = **adopter la lib
  comme style de code du repo** — soit précisément « toucher au code réel », ce que
  l'utilisateur veut éviter.
- **Construire le bijection nous-mêmes est un mini-compilateur C#.** Un mapping
  d'alias fiable (et son inverse) demande un **parseur sémantique** C# (Roslyn), pas
  des regex : résoudre les `using`, les surcharges, les génériques, l'inférence de
  type pour réétendre `ok1()` → le bon `FirstOrDefaultAsync/Ok/NotFound` au bon
  type. C'est l'« AST transform » que le projet **n'a même pas**.

Même conclusion de forme que caveman-code (frères Pi) : *au niveau idée, oui ;
en bloc, non.* Sauf qu'ici l'idée elle-même bute sur la réversibilité.

## 3. « Ça s'intègre à une extension OMP ? » — le vecteur existe, le Out est un piège

Les hooks OMP (vérifiés dans `extensions/` token-diet + caveman-code.md §2) offrent
bien les deux côtés d'un adapter :

| Côté | Hook OMP | Rôle |
|---|---|---|
| **In** (fichier → modèle) | `tool_result` sur `read` (modifier le résultat) **ou** `context` (messages → messages, deep copy) | minifier le code avant que le modèle le voie |
| **Out** (modèle → fichier) | `tool_call` sur `write`/`edit` (`{ block, reason }` ou réécriture d'input) | ré-étendre le minifié avant l'écriture disque |

Mécaniquement faisable. **Mais trois blocages d'ingénierie, par ordre de gravité :**

1. **La surface d'édition d'OMP travaille sur les octets réels.** `edit` fait un
   remplacement de chaîne sur le fichier disque ; `read-dedup` empreinte
   `taille:mtime`. Si le modèle voit la **vue minifiée** mais que le disque porte le
   **verbeux**, chaque `old_string` que le modèle compose (depuis ce qu'il voit) ne
   matche **rien** sur disque. Il faudrait soit (a) stocker le minifié comme
   canonique sur disque — donc *toucher au repo*, prémisse violée — soit (b)
   maintenir deux représentations synchronisées et **remapper chaque édition** d'une
   vue à l'autre : numéros de ligne, diffs, grep, blame, *tous* divergent.
2. **Le Out n'est correct que si le modèle écrit dans le dialecte exact.** L'expander
   suppose une grammaire d'alias stricte. Dès que le modèle produit du C# idiomatique
   normal (ce qu'il fait par défaut, voir §5), l'expander n'a rien à étendre — ou pire,
   étend de travers.
3. **L'expansion fiable = Roslyn en pré-écriture, ×N agents.** Lancer une analyse
   sémantique C# avant chaque `write`/`edit`, multiplié par les 32 agents du dev-team,
   c'est la même dépendance lourde + latence que le binding ONNX/BERT **différé**
   dans caveman-code.md §6.

Autrement dit : OMP *peut* héberger un adapter ; mais un adapter de **code**
(vs de *prose*/contexte) entre en collision avec le modèle d'édition byte-exact qui
fait la fiabilité d'OMP. token-diet a délibérément cantonné ses transforms au
**contexte** (assistant/tool), jamais au code que le modèle va éditer.

## 4. « Gain réel en tokens ? » — étroit, C#-only, et déjà capté en grande partie

- **Les chiffres annoncés mesurent l'adoption-style, pas l'adapter.** Les 10–25 %
  supposent qu'on **écrit** en `Smoower.Minified` (le modèle *émet* `ok1()`). En
  adapter qui ne touche pas au repo, pour récupérer le gain *output* il faudrait que
  le modèle **génère** dans le dialecte — donc qu'on lui **injecte le dictionnaire
  d'alias** (coût input à chaque tour) et qu'il raisonne dedans (§5). Le gain ne
  porte que sur le code généré, pas sur le tour entier.
- **Côté input (montrer les fichiers), le levier sûr est quasi nul.** Sur du code,
  le seul transform sans perte est le whitespace — et `context-compress` niveau
  `safe` **strippe déjà** ANSI + espaces de fin + runs d'espaces (indentation
  préservée). Les gros gains de `Smoower.Minified` viennent du **renommage
  d'identifiants** (`Users`→`U`, alias) : c'est exactement ce que `protect.ts`
  **protège byte-identique** (empans `\b\w+(?:[._:#$/-]\w+)+\b`, fenced/inline code).
  Le marginal d'un adapter qui minifie le code, **au-delà** de ce que la pile
  lossless capte déjà (read-dedup + context-dedup + `safe`), est faible.
- **Le mapping de noms a un coût caché.** Un renommage projet-wide bijectif
  (`Users`↔`U`) doit transporter son **dictionnaire** en contexte (coût input) et
  **casse grep/CodeGraph/symbol-search** : on cherche `UserRepository`, le modèle ne
  voit que `UR`. token-diet pousse au contraire CodeGraph (requêtes symbole/call-graph)
  — un renommage opaque va à l'envers de cette stratégie.
- **Strictement C#/ASP.NET/EF.** token-diet vise multilingue (EN/FR/RO, filtres
  ctx-wire). Un adapter mono-stack a une couverture étroite face à l'effort.

**Verdict Q2 :** gain réel **mais marginal et risqué** une fois soustrait ce que la
pile lossless existante capte déjà ; le delta exploitable est précisément la partie
**non sûre** (renommage d'identifiants).

## 5. « Effort supplémentaire au modèle ? » — oui, et c'est le point décisif

C'est là que le compte penche clairement du mauvais côté.

- **Dialecte hors-distribution.** Les modèles sont entraînés massivement sur du C#
  idiomatique verbeux. `ok1()`, `nt()`, `w()`, `s()` sont *out-of-distribution* : le
  modèle doit (a) charger le dictionnaire d'alias en mémoire de travail, (b) encoder
  son intention dedans, (c) le tout sans les ancrages sémantiques habituels. → **plus
  de tokens de raisonnement**, **plus d'hallucinations** de noms de méthodes, erreurs
  sémantiques subtiles (mauvaise surcharge, mauvais type de retour).
- **Le projet l'admet implicitement.** Le niveau L2 n'existe *« with tooling
  support »* (analyzers) — un aveu que sans assistance, le dialecte mappé n'est pas
  tenable. Un humain a un analyzer dans l'IDE ; le modèle, lui, paie en contexte +
  raisonnement.
- **On repaie le gain I/O en thinking + retries.** Économiser 25 % d'octets sur le
  fil mais ajouter des tokens de réflexion *et* un cycle de correction (le code
  minifié compile-t-il ? la surcharge est-elle la bonne ?) donne un **net token
  potentiellement négatif** sur du travail à fort raisonnement — et une qualité plus
  basse.
- **Décision déjà prise dans token-diet.** caveman-code.md §2/§5 a écarté la
  réécriture des **empans de code** et du **prompt user** pour exactement ce motif :
  *« compresser les instructions/le code est le moyen le plus sûr de corrompre
  l'intention »*. Le protect mask existe précisément pour **ne jamais** toucher au
  code. Un adapter de minification ferait le contraire de cette doctrine.

**Verdict Q3 :** oui, l'effort modèle augmente (raisonnement + qualité), et il
**annule probablement** le gain input/output sur les tâches non triviales. C'est le
risque que token-diet a structurellement choisi d'éviter.

## 6. Synthèse des trois questions

| Question | Réponse courte |
|---|---|
| **1. Intégrable en extension OMP ?** | Le *vecteur* oui (hooks `context`/`tool_result`/`tool_call`), mais un adapter **de code** entre en collision avec l'édition byte-exact d'OMP (Out non fiable) ; et `Smoower.Minified` n'étant pas réversible, on ne l'intègre pas — on ré-implémenterait l'idée, qui bute sur la réversibilité. **Non recommandé.** |
| **2. Gain réel en tokens ?** | Réel mais **étroit et C#-only** ; la part *sûre* (whitespace) est **déjà** captée par `context-compress safe` ; la part rentable (renommage) est la part **non sûre**. Delta marginal faible. |
| **3. Sans surcoût modèle ?** | **Non.** Dialecte hors-distribution → raisonnement + erreurs ↑ ; gain I/O repayé en thinking/retries ; qualité ↓ sur tâches à raisonnement. |

## 7. Recommandation

1. **Ne pas construire l'« adapter de minification ».** Triple obstacle :
   non-réversibilité de la source, collision avec le modèle d'édition byte-exact
   d'OMP (Out), et surcoût raisonnement/qualité (dialecte OOD). Les deux premiers
   sont des murs d'ingénierie ; le troisième va contre la doctrine token-diet
   (« on protège le code, on ne le réécrit jamais »).
2. **Garder la ligne actuelle :** transforms **de contexte** sûrs (read-dedup +
   context-dedup *lossless*, `context-compress safe`), `protect.ts` qui garde le code
   byte-identique, CodeGraph pour les requêtes symbole. C'est la version *correcte* de
   « réduire les tokens sans toucher au code réel ».
3. **Si on veut vraiment gratter des tokens *output* sur C#, le faire EN
   DISTRIBUTION**, pas via un dialecte d'alias. Une **skill d'idiomes terses** qui
   demande au modèle des tournures qu'il **connaît déjà parfaitement** : `var`,
   membres expression-bodied, `namespace` file-scoped, collection expressions,
   pattern matching, primary constructors. Gain *output* réel, **zéro expansion**,
   **zéro dictionnaire**, code du repo = vrai code idiomatique (juste plus dense).
   C'est la voie `/caveman` + `/yagni`, pas un adapter — et ça reste *in-distribution*
   donc sans surcoût raisonnement. **C'est l'expérience que je proposerais** si on
   veut chasser ce levier.
4. **Si on tient à mesurer avant de trancher :** petit harnais de bench — N fichiers
   C# représentatifs, appliquer le transform d'alias, mesurer *tokens input
   économisés* **et** *qualité sur un set de tâches fixe* **et** *tokens de thinking*
   et *taux de retry*. Gater derrière un flag explicite comme `context-compress`
   (`lite`/`full`). Hypothèse attendue : net-négatif en L2/L3 sur le travail à fort
   raisonnement.

## Sources

- `Smoower.Minified` : <https://github.com/Smoower/dotnet-minified> (README : alias
  `ok1()`, niveaux L1/L2/L3, échantillon `5049 → 3785`, ≈ 38 % output, *« not
  reversible »*, *« same .NET code · fewer tokens · no magic »*)
- token-diet : `extensions/{read-dedup,context-dedup,context-compress}.ts`,
  `extensions/lib/{protect,messages}.ts` (protect mask, empans préservés byte-à-byte,
  rôles `assistant`/`tool` only, deep copy au hook `context`), `package.json`
  (`omp.extensions`), `README.md`
- Étude sœur (même format/raisonnement) : `research/caveman-code.md` (hooks OMP
  `context`/`tool_call`/`tool_result`/`input` ; doctrine « on protège le code, on ne
  réécrit ni le code ni le prompt user » ; binding ONNX/BERT différé pour latence ×N)
- LLMLingua-2 (`force_tokens`/`force_reserve_digit`) :
  <https://github.com/microsoft/LLMLingua/blob/main/DOCUMENT.md> — rappel que la
  préservation des empans techniques est *the* condition de sûreté
