# /model-routing-check — diagnose tier → model routing

Role: **worker**. Read-only diagnostic.

## Run it

1. `read skill://model-routing-check` and follow it.
2. Print the effective tier → model map from `skill://dev-team-knowledge/model-routing.json`
   and `.omp/config.yml` `modelRoles`, the local backend probe status, and the
   most recent dispatches from `.omp/state/model-routing.log`.

Quick version: run the `/routing` command (registered by the `model-routing`
extension) for a one-line status.
