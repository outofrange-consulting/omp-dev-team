# local-llm

> 🌐 [English](README.md) · **Français**

Faites tourner les rôles d'OMP sur des **modèles locaux dimensionnés à votre
matériel**. Détecte la VRAM/RAM, choisit les meilleurs modèles GGUF **par rôle**,
installe le backend (**Ollama** ou **llama.cpp**), télécharge les modèles, et les
enregistre comme fournisseur `local-llm`.

Hybride par défaut : la **planification reste dans le cloud** (Opus) ;
l'**exécution et les rôles bon marché tournent en local**, à coût de tokens nul.

## Installation

```sh
omp plugin install local-llm@omp-dev-team
bash plugins/local-llm/install.sh          # détecte → demande → installe → pull → câble
#   pwsh -File plugins/local-llm/install.ps1   # Windows
```

L'installeur **demande d'abord** (et avertit sous 8GB de VRAM), puis installe le
backend choisi, télécharge les modèles de rôle, et ajoute le câblage des rôles à
`~/.omp/agent/config.yml`. Options : `--backend ollama|llama.cpp`, `--vram=N
--ram=N`, `--all` (télécharge tous les modèles compatibles), `--apply-config`,
`--dry-run`, `-y`.

## Fonctionnement

- **`extensions/lib/catalog.ts`** — la carte des tiers : pour chaque modèle, la
  VRAM (totale / sur carte avec offload), l'offload RAM (MoE), la qualité et les
  rôles éligibles.
- **`selector.ts`** — classe chaque modèle pour votre machine (`oncard` /
  `moe-offload` / `dense-spill` / `no-fit`), score qualité×vitesse, et attribue le
  meilleur par rôle (`smol`/`commit` prennent le plus petit rapide qui rentre).
- **`extensions/local-llm.ts`** — au démarrage, détecte le matériel et enregistre
  les modèles compatibles comme fournisseur `local-llm` (`pi.registerProvider`) ;
  `/local-llm` relance la détection et affiche le plan + le YAML des rôles. Ce
  fichier est aussi le CLI (`bun extensions/local-llm.ts --json`) qui pilote
  l'installeur.

## Rôles — conservateur par défaut (`--level`)

Un modèle local ne prend un rôle **que s'il sait bien le faire**. Par défaut, le
local se limite aux rôles bon marché / à fort volume ; on en demande plus avec
`--level` :

| `--level` | Rôles locaux | Rôles cloud |
|---|---|---|
| **`smol`** (défaut) | `smol`, `commit`, `vision` | `plan`, `default`, `task`, `slow` |
| **`balanced`** | + `task`, `slow` (si un modèle fort rentre, sans spill) | `plan`, `default` |
| **`max`** | + `default` (seulement si un top modèle tient *entièrement sur le GPU*) | `plan` |
| **`local-only`** | tout | — |

L'escalade dépend du fit réel, pas seulement du flag : en 16GB, `max` garde quand
même `default` sur le cloud (le 30B est en offload d'experts) ; en 24GB+, il promeut
un top modèle en `default`. `plan` reste cloud sauf en `local-only`. Réglez le
niveau avec `--level=…` ou `OMP_LOCAL_LEVEL`.

## Backends

- **Ollama** (défaut, recommandé) : multi-modèles, offload d'experts auto, OMP le
  découvre sur `:11434`. L'installeur télécharge chaque modèle de rôle.
- **llama.cpp** (avancé) : un modèle par `llama-server` (`:8080`) ; l'installeur
  installe le binaire et affiche la commande de lancement recommandée pour votre
  modèle principal. Mettez `OMP_LOCAL_BACKEND=llama.cpp`.

## Surcharges

`OMP_LOCAL_VRAM_GB`, `OMP_LOCAL_RAM_GB` (forcer le plan), `OMP_LOCAL_BACKEND`
(`ollama`|`llama.cpp`). Éditez `catalog.ts` pour ajouter/régler des modèles — c'est
*la* carte.

Se marie avec **copilot-preset** (cloud bon marché pour plan/default) et
**dev-team** (pointez son petit tier vers un modèle `local-llm/…`). Indépendant
des autres plugins.
