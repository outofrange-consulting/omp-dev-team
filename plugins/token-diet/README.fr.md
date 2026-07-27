# token-diet

> 🌐 [English](README.md) · **Français**

Réduction de tokens pour [Oh-My-Pi](https://github.com/can1357/oh-my-pi), ramenée
à ce qu'OMP ne fait **pas** déjà.

| Couche | Rôle |
|---|---|
| **[lean-ctx](https://github.com/yvgude/lean-ctx)** (MIT) | Un binaire Rust local entre l'agent et ses outils. `bash`, `read`, `grep`, `find` et `ls` y sont routés : la sortie des commandes **et** les lectures de fichiers, résultats de recherche et contexte projet sont compressés, 75+ outils sont reconnus d'emblée, et un cache de session persistant rend une relecture inchangée bien moins chère. |
| Skill **`caveman`** | **Sortie** d'agent laconique. Le seul axe que rien d'autre ne traite — OMP et lean-ctx travaillent tous deux sur ce qui *entre* dans le modèle. Préserve la langue de l'utilisateur. |
| Extension **`path-inject`** | Met `~/.local/bin` sur le PATH d'OMP. Le snapshot shell d'OMP lance `bash -c`, qui ne source aucun profil : les outils installés là restent invisibles jusqu'à un nouveau shell de login. |

## Installation

```sh
bash plugins/token-diet/install.sh
```

Installe lean-ctx (brew, puis l'installeur officiel, puis npm), miroite
l'extension `pi-lean-ctx` d'amont depuis npm vers `~/.omp/agent/extensions/`, et
fusionne `config.snippet.yml`. lean-ctx est **non fatal** : si le téléchargement
échoue, l'installation continue et vous indique comment réessayer.

## Ce que ce plugin ne livre volontairement plus

Chaque suppression parce qu'OMP ou lean-ctx le fait mieux :

| Retiré | Remplacé par |
|---|---|
| `ctx-wire` + un filtre TOML écrit à la main par commande | lean-ctx — ne compresser que la sortie des commandes imposait un filtre par commande ; quatre pour `dotnet` à lui seul |
| `read-dedup`, `context-dedup` | `compaction.supersedeReads` (actif par défaut), `dropUseless`, `pruneToolOutputs` |
| `cache-meter`, `/cache-health` | segments natifs de statusline `cost`, `cache_read`, `cache_write`, `cache_hit` |
| `context-compress` | lean-ctx ; le nôtre était désactivé par défaut et sa fenêtre glissante mutait le préfixe déjà envoyé, cassant le cache de prompt |
| `tools.discoveryMode`, `tools.essentialOverride` | **supprimés dans OMP 17.0.0** et effacés de la config au chargement — `tools.xdev` les remplace sans configuration |
| le « scrub » de secrets in-process | `secrets.enabled` + `~/.omp/agent/secrets.yml`. L'ancien *préservait* les spans à haute entropie au lieu de les retirer — il n'a jamais rien redacté |
| skills `yagni`, `atlassian`, `context7`, `mcp-as-cli-skill-creator` | `yagni` supprimé ; Atlassian et Context7 sont câblés sur leurs **serveurs MCP officiels** par l'installeur racine |

## Configuration

Les réglages de lean-ctx vivent dans `~/.pi/agent/extensions/pi-lean-ctx/config.json`
— cette extension résout sa config contre `~/.pi`, pas `~/.omp`, donc l'installeur
l'écrit là où elle la lit réellement. `mode: replace` remplace carrément les outils
natifs ; `additive` (défaut ici) laisse les deux disponibles.

## Mesurer

`omp usage --history` et `omp stats` donnent de vrais chiffres de tokens et de
coût. Le segment `cache_hit` de la statusline indique si le cache de prompt est
touché. Aucun gain annoncé ici n'a été mesuré sur votre charge — mesurez avant de
faire confiance à un chiffre.
