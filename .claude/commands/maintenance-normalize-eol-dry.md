# maintenance-normalize-eol-dry

Lance la maintenance "normalize-eol" en dry-run et produit un rapport Markdown prêt pour Notion.

## Run
- bash: MAINT_TASK=normalize-eol MODE=dry ./scripts/maintenance/run-maintenance.sh

## Output attendu
- logs/maintenance/normalize-eol_*.log
- reports/normalize-eol_*.json
- docs/notion/exports/normalize-eol_*.md
