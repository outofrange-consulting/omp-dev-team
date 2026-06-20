# datadog

Observabilité Datadog depuis le terminal pour Oh-My-Pi, via la CLI Datadog
**[`pup`](https://github.com/DataDog/pup)** — un binaire unique avec plus de 200
commandes couvrant les produits Datadog (logs, métriques, traces/APM, monitors,
incidents, dashboards, SLO, synthetics, RUM, sécurité/audit, visibilité des
tests CI, observabilité LLM/agent).

## Un seul skill, volontairement

`pup` embarque une trentaine de skills/subagents par domaine. Les exposer
individuellement saturerait la liste des skills d'OMP : ce plugin fournit donc
**un seul** skill large `datadog` qui pilote la CLI `pup`. La CLI porte les
skills par domaine en interne (`pup skills list`) et l'agent découvre les
commandes exactes avec `pup --help`.

## Installation

```sh
bash plugins/datadog/install.sh
#   pwsh -File plugins/datadog/install.ps1     # Windows
```

Ce que fait l'installeur :

1. Installe la **CLI pup** — via Homebrew (`datadog-labs/pack/pup`) si dispo,
   sinon le binaire de release préconstruit dans `~/.local/bin` (sans sudo).
2. Configure l'**authentification** : `pup auth login` (OAuth, navigateur) en
   interactif, ou persiste `DD_API_KEY`/`DD_APP_KEY`/`DD_SITE` dans
   `~/.omp/secrets.env` (chmod 600).
3. Laisse le skill large `datadog` router le tout via pup.

Options : `--with-skills` (exécute aussi `pup skills install pi` pour ajouter les
skills par domaine comme skills OMP de premier plan — désactivé par défaut),
`--no-config` (saute l'auth), `-y` (non interactif).

## Utilisation

Une fois authentifié, demande en langage naturel (« investigue l'alerte de
latence sur checkout-service », « montre les logs d'erreur de payments sur la
dernière heure », « trie les tests instables qui bloquent ma PR »). Le skill
`datadog` pilote `pup`. Manuellement :

```sh
pup auth status
pup --help
pup skills list
```

## Notes d'authentification

- OAuth (`pup auth login`) est préféré ; il requiert l'enregistrement dynamique
  de client (DCR) activé sur ton site Datadog.
- Repli : `export DD_API_KEY=… DD_APP_KEY=… DD_SITE=datadoghq.com` (utilise ta
  région, ex. `datadoghq.eu`, `us5.datadoghq.com`).
