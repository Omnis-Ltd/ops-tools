.PHONY: help repo-health normalize-eol-dry normalize-eol-apply

help:
	@echo "Targets:"
	@echo "  repo-health           - Diagnostic rapide des repos"
	@echo "  normalize-eol-dry     - Dry-run normalisation LF"
	@echo "  normalize-eol-apply   - Apply + renormalize + commit (skip dirty)"

repo-health:
	@./scripts/maintenance/repo-health.sh

normalize-eol-dry:
	@./scripts/maintenance/normalize-eol-batch.sh --dry-run

normalize-eol-apply:
	@./scripts/maintenance/normalize-eol-batch.sh --apply --renormalize --commit --skip-dirty
