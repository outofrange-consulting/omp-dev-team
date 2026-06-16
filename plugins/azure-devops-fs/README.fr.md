# azure-devops-fs

> 🌐 [English](README.md) · **Français**

**Azure DevOps comme un système de fichiers pour [Oh-My-Pi](https://github.com/can1357/oh-my-pi).**
L'équivalent ADO du « GitHub comme système de fichiers » d'OMP (`pr://` / `issue://`
+ l'outil `github`). Autonome — ne dépend d'aucun autre plugin.

Comme les schémas d'URL internes `xxx://` d'OMP sont enregistrés dans le cœur (non
extensibles), ce plugin fournit le même modèle via un outil dédié, `ado`, qui rend
les chemins/réfs de première classe et comprend les URIs `ado://` / `adopr://`.

## Capacités

- **Lecture** (cache dans `~/.omp/cache/ado-cache.db`) : `repo_view`, `repo_ls`,
  `repo_read`, `pr_view` (threads + statut de merge + relecteurs requis + work
  items liés), `pr_list`, `pr_files`, `pr_diff`, `work_item`, `search_code`.
- **Gates / CI** (spécificités Azure) : `pr_checks` (**évaluations** des stratégies
  de branche + **statuts** PR externes + **builds de validation** + `mergeStatus`/
  conflits — la porte de merge, comme les required checks GitHub), `pipeline_list`,
  `build_list`, `build_logs`, `build_run` (déclenche), `pipeline_watch` (poll).
- **Écriture** : `pr_create`, `pr_checkout` (clone la branche de la PR dans
  `~/.omp/wt/...`), `pr_push`, `pr_comment`, `pr_vote`, `pr_complete` (merge /
  auto-complétion avec `mergeStrategy`), `pr_abandon`, création de `work_item`.
- **Pagination** : `pr_files`/`pr_diff` paginent les changements d'itération de la
  PR ($top/$skip) pour ne jamais tronquer les grosses PR (`pr_diff` 25 fichiers/page
  via `skip=`) ; les listes builds/pipelines suivent `x-ms-continuationtoken`. Les
  fichiers binaires des diffs sont ignorés.
- **URIs** : `ado://{org}/{project}/{repo}/{path}@{ref}`,
  `adopr://{org}/{project}/{repo}/{id}[/diff[/path]]` (org/projet par défaut depuis l'env).
- **Commandes** : `/ado`, `/ado-pr`, `/ado-review`, `/ado-pipeline`.
- **Skill** : `skill://azure-devops-fs`. **Règle** : sûreté du PAT.

## Mise en place

```sh
omp plugin install azure-devops-fs@omp-dev-team
bash plugins/azure-devops-fs/install.sh     # assure Node + demande org/projet/PAT
```

L'installeur (interactif) demande votre org/projet/**PAT** et les persiste
(org/projet dans votre profil shell ; le PAT dans `~/.omp/secrets.env`, chmod 600,
sourcé depuis votre profil). Pour les définir à la main à la place :

```sh
export AZURE_DEVOPS_ORG=votre-org
export AZURE_DEVOPS_PROJECT=votre-projet     # défaut optionnel
export AZURE_DEVOPS_PAT=xxxxxxxx             # Code R/W, PR R/W (+ Build R pour les pipelines)
```

## Notes de conception

- L'auth est injectée par requête (en-tête REST ; git `http.extraheader`) — le PAT
  n'est jamais écrit sur disque ni dans les URLs distantes.
- Les lectures sont mises en cache ~120s, cloisonnées par empreinte du PAT
  (`OMP_ADO_CACHE=0` pour désactiver).
- Les opérations destructrices (`pr_abandon`, `pr_vote reject`, push forcé)
  exigent une confirmation (invite UI, ou `confirm: true` en mode headless).
- `pr_diff` reconstruit un diff unifié via `git diff --no-index` sur les blobs base
  vs source (ADO n'a pas d'endpoint de diff unifié unique).

## Backend

L'outil `ado` pilote l'**Azure CLI** (`az` + l'extension `azure-devops`) :
commandes haut-niveau `az repos`/`az pipelines`/`az boards` quand elles existent,
et `az devops invoke` pour les endpoints bruts (items, itérations, threads,
statuts, évaluations de policy, logs). Comme il passe par `az`, il hérite du
magasin de certificats et du proxy de l'OS — donc il fonctionne derrière les
proxys TLS d'entreprise (Zscaler / Trend Micro sous WSL). Auth par PAT (exporté
en `AZURE_DEVOPS_EXT_PAT`, ou `az devops login`). Par-dessus, `ado` ajoute le
modèle de système de fichiers `ado://`, un cache de lecture, des worktrees de PR,
et le flux `/ado-review`.

Voir [`knowledge/ado-api-reference.md`](knowledge/ado-api-reference.md) pour le
mapping op → REST.
