# copilot-preset

> 🌐 [English](README.md) · **Français**

Une **configuration de modèles prête à l'emploi** qui route [Oh-My-Pi](https://github.com/can1357/oh-my-pi)
— et, s'il est installé, le plugin **dev-team** — via **GitHub Copilot**
(fournisseur `github-copilot`). Pour les équipes qui paient déjà Copilot et veulent
un réglage **solide mais bon marché** qui limite la dépense de tokens.

Autonome et config seulement : il fournit un skill + un extrait de config + une
référence tarifaire. Il n'a **délibérément aucune extension** — le routage des
modèles (`modelRoles`) est un réglage utilisateur, donc vous collez l'extrait
plutôt qu'un plugin ne le fixe.

## Mise en place

```sh
omp plugin install copilot-preset@omp-dev-team

# 1) authentifier Copilot
omp            # puis /login -> GitHub Copilot   (OAuth)
#   ou : export COPILOT_GITHUB_TOKEN=...

# 2) voir ce que votre plan expose (récupéré en direct depuis votre compte Copilot)
omp --list-models | grep github-copilot

# 3) coller config.snippet.yml dans ~/.omp/agent/config.yml (ajuster les ids)
```

> `COPILOT_GITHUB_TOKEN` est la **seule** variable d'environnement lue par ce
> fournisseur — il n'y a **aucun** repli sur `GH_TOKEN` / `GITHUB_TOKEN`. Le
> descripteur de fournisseur d'OMP déclare un tableau `envVars` à un seul
> élément, et le résolveur d'identifiants construit une recherche à clé unique à
> partir de celui-ci. (Le `packages/ai/README.md` d'amont annonce encore un
> repli ; ce texte est périmé.)

## La facturation a changé le 2026-06-01

Copilot est passé des unités de « premium request » à des **crédits IA à l'usage** :
vous payez au token (entrée/caché/écriture cache/sortie) au tarif de chaque modèle
(1 crédit = 0,01 $). Choisir le bon modèle par rôle est désormais un levier direct
en $. Table complète, allocations par plan, pièges d'accessibilité et comparatif
du moins cher au plus cher : **[`pricing.md`](pricing.md)**.

## Ce qu'il règle (« solide mais bon marché »)

**Les huit rôles routés sont réglés explicitement** — c'est l'objet même de cet
extrait, pas un hasard. OMP n'a de chaînes de priorité intégrées que pour
`smol`/`slow`/`designer` : un `plan` non réglé retombe donc silencieusement sur
le modèle de votre *session*, et `@task` hérite de la session par conception.
L'un comme l'autre annule discrètement un « tier bon marché ».

| Rôle | Tier | Modèle | entrée / sortie (par 1M) |
|---|---|---|---|
| `smol` | nano (lexical/scan) | `github-copilot/gpt-5-mini` | 0,25 $ / 2,00 $ |
| `task` | code (coding/tool-use) | `github-copilot/mai-code-1-flash-picker` | 0,75 $ / 4,50 $ |
| `default` / `plan` | balanced (+ design archi/domaine) | `github-copilot/claude-sonnet-5` | **2,00 $ / 10,00 $** ⏳ |
| `designer` | UI/UX + a11y | `github-copilot/gemini-3.1-pro-preview` | 2,00 $ / 12,00 $ |
| `vision` | traitement d'images | `github-copilot/gpt-5-mini` | 0,25 $ / 2,00 $ |
| `advisor` | second avis (désactivé par défaut) | `github-copilot/gpt-5.3-codex` | 1,75 $ / 14,00 $ |
| `slow` | deep (verdicts sécurité) | `github-copilot/claude-opus-4.8` | 5,00 $ / 25,00 $ |

`tiny` et `commit` sont **délibérément non réglés** : OMP fait déjà pointer
`tiny` sur la chaîne `smol` et résout `commit` via `["commit","smol",…]` — les
régler ici serait sans effet.

⏳ **Le tarif 2 $/10 $ de Sonnet 5 est promotionnel jusqu'au 2026-08-31** et le
tarif post-promo n'est pas publié. À revérifier le 2026-09-01 ;
`github-copilot/gpt-5.6-terra` (2,50 $/15 $, contexte 1,05M) est déjà en tête de
la chaîne de repli de `default`, précisément pour cette raison.

Il règle aussi `modelProviderOrder: [github-copilot]` (une préférence : la copie
servie par Copilot gagne les résolutions de rôle ambiguës), `retry.fallbackChains`
avec une entrée joker de fournisseur `"github-copilot/*": ["anthropic/*"]`, et
`advisor.enabled: false`.

**`enabledModels: [github-copilot/*]` est livré commenté.** C'est un tableau,
donc n'importe quelle couche de config supérieure le remplace entièrement ; un
motif sans correspondance produit une liste de modèles **vide** *sans* repli (la
session casse au lieu de se dégrader) ; et cela ferme la porte aux fournisseurs
open-weight non-Copilot déjà supportés par OMP (cerebras/GLM, qwen-portal,
moonshot, deepseek). Ne le décommentez que si vous voulez délibérément un
verrouillage d'équipe strict.

## MAI-Code-1-Flash (« MIA Coding »)

Le modèle de Microsoft, bon marché et taillé pour le code (0,75 $ / 4,50 $,
contexte 256K, **sortie max 128K**), disponible (GA) sur Copilot depuis le
2026-06-02. Il bat Claude Haiku 4.5 sur tous les benchs coding publiés par
Microsoft (SWE-Bench Verified 71,6 vs 66,6, SWE-Bench Pro 51,2 vs 35,2, Terminal
Bench 2 54,8 vs 41,6) avec jusqu'à 60 % de tokens en moins — et il est moins cher
que Haiku (1 $/5 $). L'extrait route le **tier `task` (code)** sur lui
(implémentation post-plan + revue structurelle), tandis que `smol` (nano,
lexical) descend sur `gpt-5-mini` encore moins cher.

> **⚠ MAI est le seul modèle sans vision de tout le catalogue Copilot**
> (modalités d'entrée `["text"]`). Comme `task` tourne dessus, ce préréglage
> **fixe `modelRoles.vision`** — `inspect_image` résout `@vision → @default →`
> modèle actif puis échoue en dur sur un modèle texte seul. Ne déplacez jamais
> MAI sur `default` sans un `vision` fixé.

**À propos de l'ancien avertissement « VS Code seulement / 400
`unsupported_api_for_model` » :** il n'a pas pu être reconfirmé. La table des
clients de GitHub montre désormais MAI disponible sur toutes les surfaces, **CLI
comprise**, et les 400 venaient bien plus probablement d'un bug côté OMP,
corrigé : `@oh-my-pi/pi-catalog` 17.0.1 (2026-07-16) a fait passer les modèles
`mai-*` par `/responses` au lieu de `/chat/completions` (issue #5612). Si votre
tenant renvoie encore 400, `retry.fallbackChains.task` prend le relais.

## Option open-weight : Kimi K2.7 Code

`github-copilot/kimi-k2.7-code` est le **premier et unique modèle open-weight de
Copilot** (poids sous licence Modified-MIT, 1T/32B MoE, contexte 256K, capable de
vision), et sa **sortie à 4,00 $ passe sous les 4,50 $ de MAI**.
`config.snippet.yml` le livre en **option commentée** clairement identifiée sur
`task` plutôt qu'en défaut, pour deux raisons : son `maxTokens` est de **32K
contre 128K pour MAI**, donc une grosse tranche d'implémentation en un seul jet
peut être tronquée — et `task` *est* le tier de build — et il est **désactivé par
défaut sur les tenants Business/Enterprise** tant qu'un admin n'active pas la
politique. Décommentez le bloc pour l'adopter ; il garde MAI en tête de la chaîne
de repli.

À noter : la gamme open-weight plus large que l'on pourrait attendre n'est **pas**
sur Copilot — GPT-OSS, Qwen, DeepSeek, GLM, Llama et Mistral sont tous absents, et
xAI/Grok a été retiré en 2026-05. OMP en supporte plusieurs nativement via
d'autres fournisseurs, ce qui est l'argument contre le verrouillage de
`enabledModels` sur Copilot.

## Notes

- **Les ids de modèles varient selon le plan/la date** — le fournisseur
  `github-copilot` découvre les modèles en direct depuis votre compte ; confirmez
  donc les ids avec `omp --list-models | grep github-copilot` avant d'éditer
  l'extrait. `pricing.md` indique lesquels sont tarifés mais inaccessibles
  (`gpt-5.4-nano`, `raptor-mini`, `gemini-3-flash-preview`, `gemini-2.5-pro`) et
  lesquels sont retirés mais toujours listés (`gpt-4.1`, `gpt-5.2`,
  `gpt-5.2-codex`, `claude-sonnet-4`, `grok-code-fast-1`).
- **Deux pièges de facturation** — franchir un seuil de contexte long retarife la
  requête **entière** (pas seulement l'excédent), et le contexte 1M d'Anthropic
  est un **id de modèle distinct** (style `claude-opus-4.7-1m`), pas une option.
  Voir `pricing.md`.
- **Le cache est un vrai levier** — l'entrée cachée est ~10× moins chère
  (0,20 $ vs 2,00 $ sur Sonnet 5) ; prompts système stables et contexte réutilisé
  sont mis en cache automatiquement.
- **Interaction avec dev-team** : les agents dev-team déclarent des alias de rôle
  agnostiques du fournisseur (`@smol`, `@plan`, `@slow`, `@designer`) sous forme
  de listes de repli séparées par des virgules, donc chaque tier se résout via les
  `modelRoles` ci-dessus et aucun agent ne fige d'id Anthropic. `pi/` reste
  accepté comme préfixe hérité, mais `@` est le préfixe canonique. Voir
  `skill://copilot-preset`.
- Indépendant de `dev-team` et `azure-devops-fs`.
