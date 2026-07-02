# Mega review — omp-dev-team

Revue multi-agents (6 agents parallèles), read-only, sur l'ensemble du dépôt
(6 plugins, ~5 500 lignes TS/sh/ps1/py + manifests + docs). Chaque zone a été
compilée/testée quand c'était possible.

**Statut de build / tests (vérifiés sur cette machine) :**

| Vérification | Résultat |
|---|---|
| `bun build` des extensions dev-team (8), token-diet (11 modules), ado.ts (9 modules) | ✅ compile, 0 erreur |
| `bun test` token-diet `extensions.test.ts` | ✅ 54 checks pass |
| `python3 verify-filters.py` (ctx-wire) | ✅ 40/40 |
| `bash -n` sur les 7 `install.sh` | ✅ pass |
| `node scripts/ci-validate-json.mjs` | ✅ 23 JSON, 0 invalide |
| PowerShell (`.ps1`) | ⚠️ non vérifiable ici (pas de `pwsh`) — findings par lecture |

**Le code compile et tourne. Les problèmes sont logiques, de sécurité, et de
cohérence docs/registres — pas des cassures de build.**

---

## Les 4 thèmes majeurs

### 1. Les « guards » de sécurité sont du théâtre de sécurité (le plus important)

Les 6 guards de `dev-team` (destructive, path, freeze, spec, review-gate,
careful) sont des hooks *PreToolUse consultatifs* basés sur du matching de
sous-chaîne / glob. Ils donnent une **fausse confiance** : ils sont
contournables trivialement, par accident comme volontairement.

| Guard | Prétend bloquer | Contournement trivial | Efficacité |
|---|---|---|---|
| destructive-guard | `rm -rf`, drop/truncate, force-push, kill… | `find -delete`, `git clean -fdx`, `> f`, `truncate -s0`, `bash -c …`, obfuscation par variable ; **warn-only hors `/careful on`** ; la SAFE-list court-circuite tout (`rm -rf node_modules/../../etc`) | Très faible |
| path-guard | édition de `.env`/`*.pem`/`*.key`/`id_rsa`… | aucune couverture `bash` (`tee`/`>`/`sed -i`) ; regex **sensible à la casse** → `ID_RSA`/`.PEM` passent ; lectures non gardées ; pass silencieux si le shape d'edit ne matche pas | Faible |
| freeze-guard | écriture sur globs gelés | **aucune branche `bash`** ; écraser `.omp/state/freeze.json` suffit | Faible |
| spec-guard (.feature) | modif de specs BDD | `BASH_WRITE_RE` étroit (rate `python -c`/`ed`/heredoc) ; opt-out `OMP_ALLOW_FEATURE_EDITS=1` | Faible–moyenne |
| review-gate | `git commit` avant approve | `--no-verify` **explicitement autorisé** ; `bash -c 'git commit'` ; le `--no-verify` est détecté par `includes` donc un message de commit le déclenche | Faible |
| careful-mode | active le blocage | fichier d'état modifiable par l'agent ; **OFF par défaut** | Faible |

**Cause racine structurelle :** l'état des guards (`careful.json`, `freeze.json`,
`review-gate.json`) vit dans `.omp/state/*.json`, **modifiable par l'acteur même
qu'ils contraignent** (`echo '{"globs":[]}' > .omp/state/freeze.json`).

Bugs concrets confirmés sur pièce :
- **CRITIQUE** `destructive-guard.ts:50` — `if (SAFE.some(s => lower.includes(s))) return;` court-circuite **toute** la vérification. `rm -rf node_modules && rm -rf /etc` → AUTORISÉ.
- **HAUTE** `shared.ts:116` `globToRegExp` — pas de flag `i` → bypass par casse (macOS/Windows = mêmes fichiers).
- **HAUTE** `destructive-guard.ts:8-25` — patterns sous-chaîne ratent `rm   -rf` (espaces), `rm --recursive --force`, `rm -r -f`.
- **HAUTE** `review-gate.ts:76` — `cmd.includes("--no-verify")` matche dans le message de commit.

**Recommandation :** soit reformuler honnêtement ces guards comme *advisory*
(anti-footgun pour agent coopératif) et déplacer leur état hors d'un espace
modifiable par l'agent ; soit les durcir (tokenisation/AST, résolution de
`bash -c`, casse-insensible, couverture `bash` pour path/freeze, défaut
block-with-confirm). Ne pas les présenter comme une *barrière* de sécurité.

### 2. La fusion de config à l'install peut corrompre le YAML utilisateur

Le README promet une fusion « sans clobber » de `~/.omp/agent/config.yml` et
`mcp.json`. En réalité :
- **CRITIQUE** `scripts/merge-json.mjs` est **JSON-only** (`JSON.parse`). Le `config.yml` (YAML) n'y passe pas — il est « fusionné » par un grep/append shell (`install.sh:218-223` `cfg_add` : ajoute un bloc si `^key:` absent). Un `config.yml` formaté différemment → **2e bloc top-level `modelRoles:`** dupliqué → la plupart des parseurs YAML clobberent ou erreurent. L'inverse de la garantie annoncée.
- **RÉSOLU** `plugins/cliproxy/install.sh:84-85` — injection awk dans `models.yml` sans garantie de format : **remplacée** par `plugins/openai-compatible/` qui conserve la même logique awk + backup + validation PyYAML.
- **MOYENNE** `merge-json.mjs` dédupe les tableaux par `JSON.stringify` → deux entrées sémantiquement égales mais d'ordre de clés différent sont gardées en double (serveur MCP / rôle dupliqué).
- **MOYENNE** double `disabledProviders:` : token-diet en écrit un (incluant `github`), le global en écrit un autre (sans) → comportement dépend de l'ordre, et casse copilot-preset qui a besoin de `github`.

### 3. Chaîne d'appro : `curl|bash` non épinglé, sans checksum

~12 points de fetch-and-execute (bun, OMP, Node, ctx-wire, **Serena (dev-team) —
lancé par `uvx` depuis git, non épinglé**, acli, .NET, npm `@latest`, pup, az) tous en
`curl|bash`/`irm|iex` **sans aucune vérification d'intégrité** (aucun sha256
dans le repo). Couplé au switch `--insecure-tls` (qui désactive la vérif TLS
pour tout le run et se propage à chaque sous-installateur), un MITM — le
scénario corporate visé — obtient une RCE.

*Bonne nouvelle vérifiée :* `--insecure-tls` est **scopé au run** (pas persisté
dans le profil — seul `--ca-file` l'est, ce qui est le bon choix). Mais il peut
être **armé silencieusement** par un `OMP_INSECURE_TLS=1` resté dans
l'environnement (warn seulement sur stderr).

### 4. Gestion des secrets : trous réels

- **HAUTE** GitHub PAT : le prompt global `prompt()` (`install.sh:105`) utilise `read -r` **sans `-s`** → le PAT est **affiché à l'écran**. Puis embarqué en clair dans `mcp.json`. Sur Linux `chmod 600` suit ; sur **Windows (`install.ps1`) aucun durcissement d'ACL**. Incohérent avec les autres prompts (Azure/Datadog/acli utilisent bien `-s`/`-AsSecureString`).
- **CRITIQUE/HAUTE** `azure-devops-fs/lib/worktree.ts:31` — le PAT est passé en **argument de ligne de commande** `git -c http.extraheader=Authorization: …` → lisible via `/proc/<pid>/cmdline` & `ps` par tout process local (contredit le `ado-pat-safety.md` du plugin). Fix : passer par `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0…` (env, pas argv).
- **HAUTE** token-diet vend du « secret scrub » : les extensions **in-process** (`protect.ts`/`messages.ts`) **ne redactent rien** — elles *préservent* les spans haute-entropie à l'identique. Le seul scrub réel est le binaire externe ctx-wire + un `replace` ATATT dans `acli.toml`. Un secret entré par un autre chemin (`read .env`, résultat MCP, echo `az`/`gh`) est conservé tel quel.
- **MOYENNE** `acli.toml:20` — regex `ATATT…` seul → rate `ATCTT…` (Confluence/Bitbucket) et tout autre préfixe Atlassian.
- **MOYENNE** `azure cache.ts` — `ado-cache.db` (SQLite) stocke les corps de réponse ADO (diffs, contenus de fichiers, logs) **en clair, sans `chmod 600`**, jamais nettoyé. (Le PAT lui-même n'est pas stocké.)
- **RÉSOLU** openai-compatible : la clé API n'est **plus jamais exportée** dans `.profile` ni dans `User env` Windows — seules `OAI_PROVIDER_URL` et `OAI_PROVIDER_NAME` le sont. La clé reste dans `~/.omp/<name>.key` (chmod 600) uniquement.
- **MOYENNE** datadog : clés exportées dans **tous** les shells (`.profile`) ou en **User env Windows en clair** → surface d'exposition large.

*Bon point vérifié :* la télémétrie (`telemetry.ts`) et le cost-metering sont
**100 % locaux**, aucun phone-home, aucun endpoint en dur.

---

## Bugs de correction notables (hors sécurité)

**token-diet :**
- **CRITIQUE** `protect.ts:36-88` — collision de sentinelle : si le texte d'origine contient déjà `NUL<digits>NUL`, `restore()` le parse comme placeholder, ne trouve pas de span, et `?? ""` **le supprime silencieusement**. Round-trip **non lossless**. Reproduit. Fix : bail-out si `text.includes(NUL)` ; renvoyer le littéral matché plutôt que `""`.
- **HAUTE** `protect.ts:134` — le niveau `safe` (défaut) collapse les espaces internes (`\S {2,}\S → \S \S`) → **détruit l'alignement** des tableaux/diffs/ASCII. Reproduit (`NAME    VALUE` → `NAME VALUE`). Contredit le « near-lossless » annoncé.
- **MOYENNE** `messages.ts:108` — la fenêtre de récence compte les messages user/system, donc les messages assistant/tool « récents » peuvent quand même être compressés.

**azure-devops-fs :**
- **HAUTE** injection de flags argv : repo/branche/ref commençant par `-` sont interprétés comme flags `az` (pas RCE — pas d'injection shell, tout passe par `execFileSync` argv, bon point — mais peut altérer le comportement `az`).
- **HAUTE** `cache.ts:34-40` — fingerprint PAT = hash 32-bit non-crypto, dégénère en `"0"` quand l'auth vient d'un fallback → cache partagé entre identités (fuite de confidentialité). Fix : sha256 sur le credential effectif, inclure org+project.
- **HAUTE** `ado.ts:315/344` — `pr_diff` : fichier introuvable renvoie « 0 files » sans erreur ; chemins affichés `a`/`b` au lieu des vrais.
- **MOYENNE** `mkdtempSync` jamais nettoyé (`ado.ts:334`, `az.ts:119`) → fuite disque (les temp `pr_diff` contiennent des contenus de fichiers).
- **BASSE** `rest.ts` est du **code mort** (transport REST parallèle non utilisé, avec sa propre logique auth/erreur subtilement différente) → supprimer ou câbler.

---

## Manifests, registres & docs

- **HAUTE** `dev-team-knowledge/index.json` — les 106 clés utilisent le préfixe `plugins/dev-team/knowledge/` **qui n'existe pas** (les fichiers sont sous `skills/dev-team-knowledge/`). 28 entrées knowledge `.md` pointent dans le vide.
- **HAUTE** `agent-registry.md` — référence **9 agents fantômes** (`angular-testing`, `csharp-quality`, `esm-enforcer`, `front-end-testing`, `go-quality`, `python-quality`, `react-testing`, `ts-enforcer`, `twelve-factor-audit`) et **oublie** `session-analysis`. L'orchestrateur route là-dessus.
- **HAUTE** « all five plugins » (Tested, EN) / « les cinq plugins » (FR) contredit « Six … plugins » dans le même README — il y en a **6**.
- **MOYENNE** token-diet `config.snippet.yml:5` mentionne un MCP `context7` qui n'existe pas (le README dit correctement : CLI+skill, pas MCP).
- **MOYENNE** README « les 8 extensions compilent sous bun » — **aucun step `bun build`/typecheck dans le workflow CI**. README EN « Verified on Linux » sous-estime le CI réel (multi-OS), le FR est juste.
- **BASSE** `package.json` racine décrit encore « Two independent plugins ».

*Vérifié OK :* 23 JSON valides, marketplace ↔ plugins ↔ plugin.json cohérent
(noms/versions/licences), 32 agents réels, ~79 skills, `omp.extensions` pointent
tous vers des fichiers existants, mcp.json = `github` only, debug/eval désactivés,
`discoveryMode: all` + `essentialOverride` présents.

---

## Priorités recommandées

**P0 — sécurité / corruption (à faire avant release)**
1. Reformuler/durcir les guards + sortir l'état de l'espace agent-writable (thème 1).
2. Fusion config YAML sans corruption : merge YAML structuré ou détection de clé YAML-aware + dédup (C1/C2 installer).
3. PAT GitHub : prompt masqué (`-s`) + ACL/owner-only Windows, idéalement `${GITHUB_TOKEN}` au lieu de baker le token.
4. PAT Azure hors argv `git` (via env `GIT_CONFIG_*`).

**P1 — correction / fuite**
5. token-diet : NUL bail-out + `safe` ne casse plus l'alignement.
6. Épingler/checksum les installeurs distants ; découpler insecure-TLS de l'exécution non épinglée.
7. Ne plus annoncer un « secret scrub » in-process ; élargir ATATT→ATCTT.
8. azure : fingerprint sha256, nettoyage temp, pr_diff (fichier introuvable), supprimer `rest.ts`.

**P2 — docs / propreté**
9. Régénérer `index.json` (bon préfixe) + réconcilier `agent-registry.md` aux 32 agents réels.
10. README : « six » partout, corriger la claim « compile sous bun » (ou ajouter le step CI), retirer `context7` du snippet, MAJ `package.json` racine.

---

*Revue générée par 6 agents spécialisés (dev-team, token-diet, azure-devops-fs,
installeurs/CI, manifests/docs, sécurité cross-cutting).*
