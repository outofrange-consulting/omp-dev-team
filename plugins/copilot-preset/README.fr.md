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
#   ou : export COPILOT_GITHUB_TOKEN=...   (repli sur GH_TOKEN / GITHUB_TOKEN)

# 2) voir ce que votre plan expose (récupéré en direct depuis votre compte Copilot)
omp --list-models | grep github-copilot

# 3) coller config.snippet.yml dans ~/.omp/agent/config.yml (ajuster les ids)
```

## La facturation a changé le 2026-06-01

Copilot est passé des unités de « premium request » à des **crédits IA à l'usage** :
vous payez au token (entrée/caché/sortie) au tarif de chaque modèle (1 crédit =
0,01 $). Choisir le bon modèle par tier est désormais un levier direct en $. Table
complète et comparatif du moins cher au plus cher : **[`pricing.md`](pricing.md)**.

## Ce qu'il règle (« solide mais bon marché »)

`modelRoles` mappant les tiers vers des modèles Copilot, `enabledModels:
[github-copilot/*]`, `modelProviderOrder: [github-copilot]` :

| Rôle | Modèle | entrée / sortie (par 1M) |
|---|---|---|
| `smol` (tier small de dev-team) | `github-copilot/gpt-5-mini` | 0,25 $ / 2,00 $ |
| `default` / `task` | `github-copilot/claude-sonnet-4.6` | 3,00 $ / 15,00 $ |
| `slow` (deep) | `github-copilot/claude-opus-4.8` | 5,00 $ / 25,00 $ |

## MAI-Code-1-Flash (« MIA Coding »)

Le modèle de Microsoft, bon marché et taillé pour le code (0,75 $ / 4,50 $),
positionné au-dessus de Haiku 4.5 en rapport prix/perf, en cours de déploiement
dans le sélecteur de modèles Copilot. L'extrait inclut un bloc commenté pour en
faire le défaut bas coût — basculez les tiers `smol`/`default` vers
`github-copilot/mai-code-1-flash` dès qu'il apparaît dans `omp --list-models`.

## Notes

- **Les ids de modèles varient selon le plan/la date** — le fournisseur
  `github-copilot` découvre les modèles en direct depuis votre compte, donc
  confirmez les ids avec `omp --list-models | grep github-copilot` et éditez
  l'extrait (jeu Anthropic actuel : Haiku 4.5, Sonnet 4.5/4.6, Opus 4.6/4.8, Fable 5).
- **Le cache est un vrai levier maintenant** — l'entrée cachée est ~10× moins chère ;
  prompts système stables / contexte réutilisé sont mis en cache automatiquement.
- **Interaction avec dev-team** : le tier small (`pi/smol`) suit ceci
  automatiquement ; les agents qui figent des ids Anthropic nécessitent un défaut
  Copilot interactif ou une édition `model:`. Voir `skill://copilot-preset`.
- Indépendant de `dev-team` et `azure-devops-fs`.
