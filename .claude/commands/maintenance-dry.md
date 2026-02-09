# maintenance:dry

Run a maintenance task in dry-run mode across tracked repositories.

## Description
This command executes a maintenance task without modifying files.
It is intended to be run before any apply/destructive operation.

## Parameters
- task (default: normalize-eol)

## Command
Run from the root of the `ops-tools` repository:

```bash
MAINT_TASK=normalize-eol MODE=dry ./scripts/maintenance/run-maintenance.sh
```

## Outputs
- logs/maintenance/<task>_<timestamp>.log
- reports/<task>/<RUN_ID>/<task>_<timestamp>.json
- docs/notion/exports/<task>_<timestamp>.md

## Notes for Claude
- Never switch to apply mode without explicit user confirmation.
- If some repositories are skipped, explain that they are out of scope (Notion Repos DB).
- Summarize the result using the generated report.
