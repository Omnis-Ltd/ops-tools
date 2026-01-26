# maintenance-normalize-eol-apply

Lance la maintenance "normalize-eol" en apply (renormalize + commit + skip dirty) et produit un rapport Markdown prêt pour Notion.

## Run
- bash: MAINT_TASK=normalize-eol MODE=apply ./scripts/maintenance/run-maintenance.sh

## Output attendu
- logs/maintenance/normalize-eol_*.log
- reports/normalize-eol_*.json
- docs/notion/exports/normalize-eol_*.md
