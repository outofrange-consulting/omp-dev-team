# Plan — Extraire de `cde-dotnetcc` pour omp-dev-team

> Statut : **IMPLÉMENTÉ** (W1+W2+W3+W4 ; vérifié — voir §Livré). En attente de revue/CI.
> Branche : `claude/repo-comparison-integration-y178js`
> Source comparée : https://github.com/atherio-danp/cde-dotnetcc (harness Claude Code .NET)
> Objectif directeur : **qualité d'abord, règles strictes, tokens Copilot minimaux.**

## Contexte

`cde-dotnetcc` est un harness de gouvernance mono-projet (Claude Code natif,
hooks PowerShell, .NET). On n'en porte pas les fichiers — on en porte les
**concepts**, adaptés au modèle OMP (extensions TS + rules/skills YAML,
cross-platform). Son principe structurant — **influence (rules/skills) vs
enforcement (deny/build-fail/état non modifiable)** — répond directement au
thème n°1 de notre `REVIEW.md` (guards advisory = « théâtre de sécurité »,
état dans `.omp/state/` modifiable par l'agent).

## Décisions verrouillées (issues de l'échange)

- **W1** Reclasser les guards influence/enforcement + sortir l'état de l'espace agent-writable. **RETENU.**
- **W2** Deux nouvelles rules strictes : *no-disable-analyzers* + *source-of-truth*. **RETENU.** (La rule « no-lib-sans-appro » n'est pas retenue pour l'instant.)
- **W3** Boucle JS déterministe pour `/build` (implement→validate→test, fixes bornés). **RETENU**, et **doit marcher aussi en .NET** (voir §W3).
- **W4** Édition symbolique : **PAS de Serena.** CodeGraph est **read-only** (vérifié : aucun outil d'édition). → On pivote vers la discipline `astEdit`/CodeGraph-first native OMP. **RETENU sous cette forme uniquement.**
- **W5** Baseline analyzers scaffoldé par projet : **ÉCARTÉ** (trop dépendant des projets).

---

## W1 — Reclasser les guards : influence vs enforcement

**Problème (REVIEW.md confirmé sur pièce).** `freeze-guard.ts` & co. chargent
leur état via `statePath(cwd, "freeze.json")` → `.omp/state/*.json` du projet,
**que l'agent peut réécrire** (`echo '{"globs":[]}' > .omp/state/freeze.json`).
Matching par substring/glob, casse-sensible, sans couverture `bash`.

**Brique d'enforcement existante.** L'extension `model-routing` prouve qu'OMP
sait **bloquer** en pré-dispatch (`permissionDecision: "deny"` via
`hookSpecificOutput`) — l'enforcement n'est donc pas le problème ; c'est (a) la
faiblesse du matching et (b) l'état agent-writable.

**Design.**
1. **Taxonomie explicite** dans `rules/dev-team-operating-manual.md` :
   - *Enforcement* (deny par défaut, non contournable) : path-guard (secrets), review-gate.
   - *Advisory* (nudge honnête, étiqueté tel quel) : freeze, tdd, careful, destructive (tant que le matching reste heuristique).
2. **Sortir l'état de l'agent-writable** dans `lib/shared.ts` :
   - `statePath()` lit d'abord `OMP_DEVTEAM_STATE_DIR` (env), défaut `~/.omp/state/<repo-hash>/` (hors arbre projet) plutôt que `./.omp/state/`.
   - Les toggles (`/freeze`, `/careful`) restent possibles mais l'état n'est plus un fichier que l'agent édite au fil de l'eau dans le repo.
3. **Durcir le matching** des guards d'enforcement (pas tous) :
   - `globToRegExp` casse-**insensible** (flag `i`) — corrige REVIEW.md HAUTE `shared.ts:116`.
   - Couverture `bash` pour path-guard (`>`, `tee`, `sed -i`) en réutilisant `bashWriteTargets`.
   - Supprimer le court-circuit SAFE-list global de `destructive-guard.ts:50` (REVIEW.md CRITIQUE) — match SAFE par commande, pas « si la chaîne contient ».
4. **Honnêteté docs** : l'operating-manual et les README cessent de présenter les guards advisory comme une *barrière*.

**Hors scope W1** : réécriture AST complète des guards destructive (gros chantier ; le plan se limite à retirer le court-circuit + casse-insensible + état déplacé + étiquetage honnête).

**Fichiers** : `plugins/dev-team/extensions/lib/shared.ts`,
`extensions/{path-guard,destructive-guard,freeze-guard,review-gate}.ts`,
`rules/dev-team-operating-manual.md`, `README.md` / `README.fr.md`.

**Vérif** : `bun build` des 8 extensions OK ; test ciblé casse-insensible + SAFE-list (ajouter à un `extensions.test.ts` dev-team si absent) ; relire que les claims README sont honnêtes.

---

## W2 — Deux rules strictes (coût token ~0)

### W2a — `rules/no-disable-analyzers.md` (path-scopé)
Reprend CLAUDE.md §Safety de cde : **« Ne jamais désactiver tests, linters ou
analyzers pour forcer un pass — corriger la cause. »** Inclut : pas de
`// eslint-disable` / `#pragma warning disable` / `[SuppressMessage]` /
`# noqa` / `--no-verify` ajoutés pour faire taire un échec ; suppression locale
justifiée seulement avec commentaire de raison + accord humain.
- `globs:` larges (`**/*.{ts,tsx,js,jsx,cs,py,go,rs,java}` + fichiers de config lint).
- Renforce, ne duplique pas, `tdd-first.md` (« never edit a failing test »).

### W2b — `rules/source-of-truth.md` (alwaysApply ou large glob)
Reprend la hiérarchie cde : **Code → DB/SQL → Télémétrie → Docs → sortie IA**.
« Aucune affirmation non citable aux rangs 1-3 ; dire *unverified* / *je ne
sais pas* plutôt que fabriquer. » Cohérent avec `output-discipline.md`
(« every quantitative claim names its instrument »). Décision : **fichier
séparé path-large** plutôt qu'`alwaysApply` pour ne pas grossir le contexte de
chaque tour (objectif token) — à trancher (voir Questions ouvertes).

**Fichiers** : 2 nouveaux `plugins/dev-team/rules/*.md`. Aucune logique, aucun build.

**Vérif** : `node scripts/ci-validate-json.mjs` n'est pas concerné ; lecture humaine + frontmatter `globs` valide.

---

## W3 — Boucle déterministe `/build` (avec support .NET)

**Constat.** Aujourd'hui `/build` est **piloté par l'orchestrateur** (l'agent
raisonne wave-by-wave, three-stage review, jusqu'à 5 itérations) → ce
« raisonnement de pilotage » consomme des tokens à chaque tour. cde externalise
ça en `impl-build.js` : control-flow JS, `maxFixes` borné, sorties contraintes
par schéma JSON, phase de test *skippable*.

**Design (port OMP).** Ajouter une **extension dev-team** (TS, pas un agent)
`extensions/impl-loop.ts` qui orchestre de façon déterministe :
1. **implement** → `task` vers `software-engineer` avec prompt focalisé + schéma de sortie.
2. **validate** → exécute la **commande de build réelle** du stack ; parse pass/fail.
3. **fix loop borné** (`maxFixes`, défaut 3) : re-`task` ciblé entre tentatives, halte sur divergence matérielle.
4. **test** → `task` vers `qa-engineer` ; exécute la commande de test ; rapporte pass/fail exacts. Skippable.

Le gain token vient de ce que **le routage des phases est en code**, pas dans le
contexte du modèle ; chaque `task` reçoit un prompt étroit.

**Support .NET (réponse à ta question : oui).** La boucle est *language-agnostic*
si build/test/format sont **configurables par stack**. Ajouter un petit registre :

```yaml
# config.snippet.yml (dev-team)
implLoop:
  maxFixes: 3
  stacks:
    node:   { build: "bun run build", test: "bun test",            format: "biome check --write" }
    dotnet: { build: "dotnet build -warnaserror", test: "dotnet test", format: "dotnet format" }
    python: { build: "ruff check", test: "pytest -q",              format: "ruff format" }
```

Détection du stack par présence de fichiers (`*.csproj`/`*.sln` → dotnet ;
`package.json` → node ; `pyproject.toml` → python), surchargable. Le stage
**validate** lance `dotnet build -warnaserror` → c'est **là** que la rule W2a
(« ne pas désactiver les analyzers ») est *vérifiée par la toolchain*, pas par
l'agent. W2 et W3 se renforcent.

> Note honnêteté : la *vérification complète* .NET de cde = build + diagnostics
> LSP (le build seul rate des analyzers IDE type IDE1006). Sans Serena, on
> s'appuie sur `dotnet build -warnaserror` + `dotnet format --verify-no-changes`.
> On documente la limite ; on ne prétend pas couvrir les analyzers IDE-only.

**Intégration `/build`.** `commands/build.md` délègue la boucle mécanique à
l'extension ; l'orchestrateur garde les gates humains et le three-stage review
sémantique (qui, eux, ont besoin d'un agent).

**Fichiers** : `plugins/dev-team/extensions/impl-loop.ts`,
`extensions/lib/shared.ts` (helper d'exécution/parse si besoin),
`package.json` (`omp.extensions`), `config.snippet.yml`, `commands/build.md`,
`skills/build/SKILL.md` (référencer la boucle).

**Vérif** : `bun build` ; `bun test` avec un cas node + un cas dotnet *mockés*
(commande qui échoue → fix loop borné → halte après `maxFixes`) ; pas d'appel
modèle réel dans les tests.

---

## W4 — Tokens à l'édition, sans Serena ni nouvel outil

**Décision.** CodeGraph = **lecture seule** (vérifié). Pas de Serena. Donc
**pas d'éditeur symbolique** ajouté. On exploite l'existant natif OMP :
`astEdit`, `astGrep`, `summarizeCode`, `blockRangeAt` (déjà cités dans
`token-diet/README.md`).

**Design (discipline, pas nouvel outil).**
1. Renforcer `token-diet/rules/token-tools.md` : pour **modifier** un symbole
   connu, utiliser `astEdit` (édition structurelle ciblée) plutôt qu'un
   `Read` full-file + `Write` full-file ; réserver le full-file rewrite aux cas
   réels. Aujourd'hui la rule couvre surtout la **lecture** (CodeGraph-first) ;
   on ajoute le pendant **édition**.
2. (Optionnel, à valider) micro-nudge advisory : si un `Write` réécrit un gros
   fichier existant quasi-identique, suggérer `astEdit`. **À ne faire que si**
   ça ne retombe pas dans le travers « guard advisory » de W1 — sinon on s'en
   tient à la rule. Recommandation : **rule seule** pour ce workstream.

**Fichiers** : `plugins/token-diet/rules/token-tools.md` (et mention courte dans son README si on documente le gain).

**Vérif** : lecture ; pas de build (rule only) sauf si on ajoute le nudge.

---

## Séquencement

1. **W2** (rules) — rapide, zéro risque, pose le socle qualité que W3 vérifie.
2. **W1** (reclassement guards) — corrige le P0 du REVIEW.md ; indépendant.
3. **W4** (rule token édition) — rapide, indépendant.
4. **W3** (boucle déterministe) — le plus gros ; bénéficie de W2 (commande build = point de vérif analyzers).

W1, W2, W4 sont parallélisables ; W3 en dernier.

## Risques & limites

- **W3** : OMP n'a pas le concept « workflows/*.js » de cde ; on l'implémente en *extension* + délégation `task`. Vérifier que `impl-loop.ts` peut piloter des `task` depuis une extension (sinon : commande scriptée). **À confirmer avant de coder W3.**
- **W1** : déplacer l'état hors `cwd` peut surprendre les workflows existants qui lisent `.omp/state/` — prévoir fallback de lecture (ancien chemin) + note de migration.
- **W4** : `astEdit` ne couvre pas tous les langages aussi bien ; rester *advisory* (« préfère ») et non bloquant.
- Ne pas régresser les claims README (le REVIEW.md pénalise déjà les incohérences docs).

## Questions ouvertes

1. **W2b** : `source-of-truth` en `alwaysApply: true` (toujours en contexte, +qualité, −tokens) ou path-large (−contexte) ? Reco : **path-large** pour l'objectif token.
2. **W1** : emplacement d'état cible — `~/.omp/state/<hash>/` vs env `OMP_DEVTEAM_STATE_DIR` obligatoire ? Reco : env override, défaut `~/.omp/...`.
3. **W3** : valider la faisabilité « extension pilote des `task` » avant de l'écrire ; sinon commande déterministe.
4. Confirmer que la rule « no-lib-sans-appro » reste **écartée**.

## Livré (deltas vs plan, après lecture du code réel)

- **W2** — `rules/no-disable-analyzers.md` + `rules/source-of-truth.md` (path-scopées, reco appliquée : pas d'`alwaysApply`). La rule « no-lib » reste **écartée**.
- **W4** — `token-diet/rules/token-tools.md` : ajout du pendant *édition* (préférer `astEdit`/`blockRangeAt` au full-file Read+Write). Pas de Serena, pas de nouvel outil (CodeGraph reste read-only).
- **W1** — recalibré : le durcissement regex que le `REVIEW.md` réclamait était **déjà fait** dans le code (path/freeze/review-gate ont déjà branche bash + block, casse-insensible, tokenisation quote-aware). Ce qui restait, livré :
  - État des guards **relocalisé hors de l'arbre projet** (`~/.omp/state/dev-team/<repoId>/`, override `OMP_DEVTEAM_STATE_DIR`, fallback lecture legacy) → `readState`/`writeState` dans `shared.ts`, câblés dans `careful-mode`, `freeze-guard`, `review-gate`, `destructive-guard`.
  - **Taxonomie honnête influence vs enforcement** dans l'operating-manual (+ note « pas un sandbox de sécurité »).
  - **Bug pré-existant corrigé** : `globToRegExp` encodait `**` via un octet **NUL brut** dans un littéral regex → mal transpilé par bun, donc les globs `**` ne matchaient **jamais** (et le NUL rendait `shared.ts` binaire). Remplacé par l'échappement textuel ` ` ; couvert par test.
- **W3** — reframé (les extensions OMP **ne peuvent pas spawner de `task`**, API réactive uniquement) : commande déterministe **`/impl-verify`** (`extensions/impl-verify.ts` + `lib/impl-verify-core.ts`) — détecte le stack, lance le **build strict + tests**, compteur de fixes borné en JS, verdict `PASS/FAIL/HALT`. **.NET natif** (`dotnet build -warnaserror` + `dotnet test`). Câblée dans `software-engineer` (comme demandé), `qa-engineer`, `/build`, et configurable via `.omp/dev-team.json` (`implVerify`).

**Vérif exécutée :** `bun build` des 28 extensions = 0 erreur ; tests unitaires dev-team (27 checks, incl. stack-detection, verdict borné, globs casse-insensibles + `**`) = pass ; token-diet (régression) = pass ; `ci-validate-json` = 23/23. Step CI « bun unit tests » ajouté.

**Reste hors scope (non régressé, à part) :** les findings P0/P1 sécurité du `REVIEW.md` non liés à ces 4 workstreams (fusion YAML installeur, PAT en argv git, checksums curl|bash, etc.).

## Définition de « done »

- `bun build` des extensions dev-team + token-diet : 0 erreur.
- Tests ajoutés (W1 casse-insensible/SAFE-list ; W3 fix-loop borné node+dotnet) : verts, output collé.
- `node scripts/ci-validate-json.mjs` : vert.
- README EN+FR cohérents avec le nouveau comportement (pas de claim non tenue).
- Plan coché workstream par workstream.
