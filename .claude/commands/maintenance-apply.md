# maintenance:apply

Run a maintenance task in apply mode (destructive) across tracked repositories.

## Description
This command executes a maintenance task and may modify files (and optionally commit),
depending on how `run-maintenance.sh` is configured for the task.

It must only be used after a successful dry-run review.

## Parameters
- task (default: normalize-eol)

## Command
Run from the root of the `ops-tools` repository:

```bash
MAINT_TASK=normalize-eol MODE=apply ./scripts/maintenance/run-maintenance.sh
```

## Safety rules
- Always run the dry-run first:
  - `maintenance:dry`
- Review the generated report/log before applying.
- Ensure target repositories are in a safe state (clean or changes committed).
- Never auto-run apply without explicit user confirmation.

## Outputs
- logs/maintenance/<task>_<timestamp>.log
- reports/<task>/<RUN_ID>/<task>_<timestamp>.json
- docs/notion/exports/<task>_<timestamp>.md
- Notion Maintenance DB entries (if NOTION_* env vars are set)

## Notes for Claude
- Ask for explicit confirmation before running apply.
- After apply, summarize:
  - how many repos were affected
  - any failures
  - where the report/log files were written
