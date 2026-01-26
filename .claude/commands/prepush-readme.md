# prepush-readme

Objectif : préparer un push propre du repo ops-tools (public) en mettant à jour le README
et en vérifiant qu’aucun secret n’est commité.

## Règles
- Ne jamais afficher de secrets (API keys, tokens).
- Ne jamais commiter .env ou fichiers contenant des clés.
- Toujours montrer `git diff` avant commit.

## Étapes
1) Vérifier l'état du repo
   - bash: git status
2) Mettre à jour la doc auto:
   - Lancer un run "repo-health" (si présent)
   - Mettre à jour l’index des runs maintenance (si présent)
3) Mettre à jour README.md :
   - Section "Quickstart" (prérequis Windows/WSL + PYTHON_BIN)
   - Section "Commands" (make targets + scripts)
   - Section "Notion" (vars attendues: NOTION_API_KEY, NOTION_BACKLOG_DB_ID, NOTION_MAINTENANCE_DB_ID, page IDs)
   - Section "Maintenance workflow" (dry → review → apply → push to Notion DB)
4) Vérifier absence de secrets :
   - bash: git grep -nE "(NOTION_API_KEY=|Bearer |sk-|api[_-]?key|token)" || true
5) Vérifier diffs et proposer commit :
   - bash: git diff
   - Proposer un message de commit clair (ex: "docs: update README (usage + notion + workflows)")

## Commandes
- bash: git status
- bash: [ -f scripts/maintenance/repo-health.sh ] && ./scripts/maintenance/repo-health.sh || true
- bash: [ -f scripts/maintenance/update-maintenance-index.py ] && PYTHON_BIN=python python scripts/maintenance/update-maintenance-index.py || true
- bash: git grep -nE "(NOTION_API_KEY=|Bearer |sk-|api[_-]?key|token)" || true
- bash: git diff

