# cliproxy

Enregistre une passerelle [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
comme **fournisseur de modèles compatible OpenAI** dans Oh-My-Pi.

CLIProxyAPI est un proxy auto-hébergé qui expose des modèles amont (Gemini,
Codex, Claude, Grok — souvent via des comptes CLI/OAuth) derrière l'API OpenAI
standard (`GET /v1/models`, `POST /v1/chat/completions`, en-tête
`Authorization: Bearer <clé>`, port par défaut `8317`). Ce plugin transforme la
passerelle en fournisseur **`cliproxy`**, utilisable sous la forme
`cliproxy/<id-modèle>` partout dans OMP.

## Installation

```sh
bash plugins/cliproxy/install.sh
#   pwsh -File plugins/cliproxy/install.ps1     # Windows
# non interactif :
bash plugins/cliproxy/install.sh --url=http://localhost:8317 --api-key=VOTRECLE
```

Ce que fait l'installeur :

1. **Demande** l'URL de la passerelle et la clé API (ou lit `--url`/`--api-key`,
   ou `CLIPROXY_URL`/`CLIPROXY_API_KEY`).
2. **Liste** les modèles de la passerelle (`GET <url>/v1/models`) pour valider la
   connexion.
3. **Écrit** un fournisseur `cliproxy` dans `~/.omp/agent/models.yml` avec
   `discovery: openai-models-list`, pour que la liste reste à jour à l'exécution.
4. Stocke la clé dans `~/.omp/cliproxy.key` (chmod 600), référencée depuis
   `models.yml` via `apiKey: "!cat …"` — jamais écrite en clair.
5. Charge l'extension pour que `/cliproxy` reliste les modèles à la demande.

## Utilisation

```yaml
# ~/.omp/agent/config.yml
modelRoles:
  default: cliproxy/gemini-2.5-flash
  smol: cliproxy/gpt-5-mini
```

`/cliproxy` reliste les modèles et réenregistre le fournisseur à chaud.

## Notes

- L'URL de base est normalisée pour se terminer par `/v1` (donc
  `http://host:8317` fonctionne).
- Relancer préserve un bloc `cliproxy` existant — supprime-le de `models.yml`
  pour le régénérer.
