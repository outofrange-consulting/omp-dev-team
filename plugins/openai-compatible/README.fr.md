# openai-compatible

Enregistre n'importe quel **endpoint compatible OpenAI** (LiteLLM, Ollama, vLLM,
LocalAI, …) comme fournisseur de modèles nommé dans Oh-My-Pi.

## Installation

```sh
bash plugins/openai-compatible/install.sh
#   pwsh -File plugins/openai-compatible/install.ps1     # Windows
# non interactif :
bash plugins/openai-compatible/install.sh --name=litellm --url=http://localhost:4000 --api-key=VOTRECLE
```

Ce que fait l'installeur :

1. **Demande** le nom du fournisseur (défaut `litellm`), l'URL de base et la clé API.
2. **Liste** les modèles de l'endpoint (`GET <url>/v1/models`) pour confirmer la
   connexion.
3. **Écrit** un fournisseur dans `~/.omp/agent/models.yml` avec
   `discovery: openai-models-list`, pour que la liste reste à jour à l'exécution.
4. Stocke la clé dans `~/.omp/<nom>.key` (chmod 600), référencée depuis
   `models.yml` via `apiKey: "!cat …"` — jamais écrite en clair ni exportée.
5. Charge l'extension pour que `/oai-provider` reliste les modèles à la demande.

## Utilisation

Définir les rôles de modèles dans `~/.omp/agent/config.yml` :

```yaml
modelRoles:
  default: litellm/claude-sonnet-4-5
  smol:    litellm/gpt-4o-mini
```

`/oai-provider` reliste les modèles et réenregistre le fournisseur à chaud.

## Notes

- L'URL est normalisée pour finir en `/v1` (donc `http://host:4000` fonctionne).
- Relancer préserve un bloc de fournisseur existant — supprime-le de `models.yml`
  pour le régénérer.
- Le nom du fournisseur est configurable : `--name=mygateway` crée un fournisseur
  `mygateway` utilisable sous la forme `mygateway/<id-modèle>`.
