# ops-tools — Home (Notion)

## Objectif
Centraliser des outils IT réutilisables :
- Maintenance (hygiène Git, normalisation, audits rapides)
- Ops (runbooks, triage incident)
- DevOps (scripts sûrs, checklists release)

## Conventions
- Fins de ligne : LF partout (y compris JSON)
- Scripts idempotents, dry-run par défaut quand c’est batch
- Toujours fournir une commande de vérification (`git diff`, `git status`, logs)

## Commandes Claude
- `scaffold` : met en place / vérifie la structure standard du repo
- `normalize-eol-batch` : normalise LF sur tous les repos sous ~/git/Workspaces
- `repo-health` : diagnostic rapide des repos (branche + dirty)

## Make targets (à compléter)
- `make help`
- `make repo-health`
- `make normalize-eol-dry`
- `make normalize-eol-apply`

## Runbooks
- `runbooks/maintenance/normalize-eol.md`
- `runbooks/maintenance/repo-hygiene.md`
- `runbooks/ops/incident-triage.md`
- `runbooks/devops/release-checklist.md`
