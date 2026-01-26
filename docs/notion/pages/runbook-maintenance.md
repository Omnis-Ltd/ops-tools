# Runbook — Maintenance Workspaces (standard)

## Objectif
- Exécuter une maintenance (dry-run puis apply)
- Produire un rapport Notion (export Markdown)
- Garder une traçabilité via l’index auto
- Lier, si pertinent, la maintenance à un item du Backlog

---

## Pré-requis
- Être dans le repo `ops-tools`
- Python fonctionnel  
  - Windows : `PYTHON_BIN=python`
  - Linux / WSL : `python3` par défaut
- Les repos à maintenir sont sous `WORKSPACES_ROOT`
  - Valeur par défaut : `~/git/Workspaces`
- Variables d’environnement disponibles si push Notion :
  - `NOTION_API_KEY`
  - `NOTION_MAINTENANCE_DB_ID`

---

## Checklist — Dry-run (obligatoire)
- [ ] Se placer dans le repo `ops-tools`
- [ ] Vérifier l’état global des repos (optionnel mais recommandé) :
  ```bash
  ./scripts/maintenance/repo-health.sh

