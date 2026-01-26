.PHONY: help repo-health normalize-eol-dry normalize-eol-apply

help:
	@echo "Targets:"
	@echo "  repo-health           - Diagnostic rapide des repos"
	@echo "  normalize-eol-dry     - Dry-run normalisation LF"
	@echo "  normalize-eol-apply   - Apply + renormalize + commit (skip dirty)"

repo-health:
	@./scripts/maintenance/repo-health.sh

normalize-eol-dry:
	@WORKSPACES_ROOT="$(HOME)/git/Workspaces" \
	./scripts/maintenance/normalize-eol-batch.sh --dry-run

normalize-eol-apply:
	@WORKSPACES_ROOT="$(HOME)/git/Workspaces" \
	./scripts/maintenance/normalize-eol-batch.sh --apply --renormalize --commit --skip-dirty

.PHONY: maintenance-normalize-eol-dry maintenance-normalize-eol-apply

maintenance-normalize-eol-dry:
	@MAINT_TASK=normalize-eol MODE=dry ./scripts/maintenance/run-maintenance.sh

maintenance-normalize-eol-apply:
	@MAINT_TASK=normalize-eol MODE=apply ./scripts/maintenance/run-maintenance.sh

