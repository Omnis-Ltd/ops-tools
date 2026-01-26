#!/usr/bin/env bash
set -euo pipefail

cleanup() {
  [[ -n "${TMP_OUTPUT_FILE:-}" && -f "$TMP_OUTPUT_FILE" ]] && rm -f "$TMP_OUTPUT_FILE"
}
trap cleanup EXIT


# Usage:
#   MAINT_TASK=normalize-eol MODE=dry ./scripts/maintenance/run-maintenance.sh
#   MAINT_TASK=normalize-eol MODE=apply ./scripts/maintenance/run-maintenance.sh

OPS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKSPACES_ROOT="${WORKSPACES_ROOT:-$HOME/git/Workspaces}"
MODE="${MODE:-dry}"  # dry | apply
MAINT_TASK="${MAINT_TASK:-normalize-eol}"

STAMP_UTC="$(date -u +"%Y%m%dT%H%M%SZ")"
STAMP_LOCAL="$(date +"%Y-%m-%d %H:%M:%S")"
HOST="$(hostname 2>/dev/null || echo unknown)"

LOG_DIR="$OPS_ROOT/logs/maintenance"
REPORTS_DIR="$OPS_ROOT/reports"
NOTION_EXPORTS_DIR="$OPS_ROOT/docs/notion/exports"

mkdir -p "$LOG_DIR" "$REPORTS_DIR" "$NOTION_EXPORTS_DIR"

LOG_PATH="$LOG_DIR/${MAINT_TASK}_${STAMP_UTC}.log"
JSON_PATH="$REPORTS_DIR/${MAINT_TASK}_${STAMP_UTC}.json"
MD_PATH="$NOTION_EXPORTS_DIR/${MAINT_TASK}_${STAMP_UTC}.md"

# --- Run task and capture output ---
{
  echo "task=$MAINT_TASK"
  echo "date_local=$STAMP_LOCAL"
  echo "date_utc=$STAMP_UTC"
  echo "host=$HOST"
  echo "ops_tools_path=$OPS_ROOT"
  echo "workspaces_root=$WORKSPACES_ROOT"
  echo "mode=$MODE"
  echo
  echo "=== OUTPUT ==="
} > "$LOG_PATH"

EXIT_CODE=0
OUTPUT=""

# --- Persist OUTPUT to a temp file (avoid env var size limits) ---
TMP_OUTPUT_FILE="$(mktemp)"
printf "%s\n" "$OUTPUT" > "$TMP_OUTPUT_FILE"


if [[ "$MAINT_TASK" == "normalize-eol" ]]; then
  if [[ "$MODE" == "dry" ]]; then
    OUTPUT="$(WORKSPACES_ROOT="$WORKSPACES_ROOT" "$OPS_ROOT/scripts/maintenance/normalize-eol-batch.sh" --dry-run 2>&1)" || EXIT_CODE=$?
  elif [[ "$MODE" == "apply" ]]; then
    OUTPUT="$(WORKSPACES_ROOT="$WORKSPACES_ROOT" "$OPS_ROOT/scripts/maintenance/normalize-eol-batch.sh" --apply --renormalize --commit --skip-dirty 2>&1)" || EXIT_CODE=$?
  else
    echo "MODE invalide: $MODE (attendu: dry|apply)" | tee -a "$LOG_PATH"
    exit 2
  fi
else
  echo "MAINT_TASK invalide: $MAINT_TASK" | tee -a "$LOG_PATH"
  exit 2
fi

# Append output to log
printf "%s\n" "$OUTPUT" >> "$LOG_PATH"
echo >> "$LOG_PATH"
echo "exit_code=$EXIT_CODE" >> "$LOG_PATH"

# --- Build a minimal JSON report (no jq required) ---
PYTHON_BIN="${PYTHON_BIN:-python}"
OPS_ROOT="$OPS_ROOT" MAINT_TASK="$MAINT_TASK" MODE="$MODE" WORKSPACES_ROOT="$WORKSPACES_ROOT" \
STAMP_UTC="$STAMP_UTC" STAMP_LOCAL="$STAMP_LOCAL" HOST="$HOST" EXIT_CODE="$EXIT_CODE" \
LOG_PATH="$LOG_PATH" JSON_PATH="$JSON_PATH" OUTPUT_FILE="$TMP_OUTPUT_FILE" "$PYTHON_BIN" - <<'PY'

import json, os

ops_root = os.environ["OPS_ROOT"]
task = os.environ["MAINT_TASK"]
mode = os.environ["MODE"]
workspaces_root = os.environ["WORKSPACES_ROOT"]
stamp_utc = os.environ["STAMP_UTC"]
stamp_local = os.environ["STAMP_LOCAL"]
host = os.environ["HOST"]
exit_code = int(os.environ["EXIT_CODE"])
log_path = os.environ["LOG_PATH"]
json_path = os.environ["JSON_PATH"]
output_file = os.environ["OUTPUT_FILE"]

with open(output_file, "r", encoding="utf-8", errors="replace") as f:
    output = f.read()

report = {
  "task": task,
  "mode": mode,
  "date_local": stamp_local,
  "date_utc": stamp_utc,
  "host": host,
  "ops_tools_path": ops_root,
  "workspaces_root": workspaces_root,
  "exit_code": exit_code,
  "log_path": log_path,
  "raw_output": output,
}

with open(json_path, "w", encoding="utf-8") as f:
  json.dump(report, f, indent=2, ensure_ascii=False)

print(json_path)
PY

# --- Render Notion-ready Markdown from template ---
PYTHON_BIN="${PYTHON_BIN:-python}"
OPS_ROOT="$OPS_ROOT" MAINT_TASK="$MAINT_TASK" MODE="$MODE" WORKSPACES_ROOT="$WORKSPACES_ROOT" \
STAMP_LOCAL="$STAMP_LOCAL" HOST="$HOST" EXIT_CODE="$EXIT_CODE" LOG_PATH="$LOG_PATH" \
JSON_PATH="$JSON_PATH" MD_PATH="$MD_PATH" OUTPUT_FILE="$TMP_OUTPUT_FILE" "$PYTHON_BIN" - <<'PY'

import os, re
from pathlib import Path

ops_root = Path(os.environ["OPS_ROOT"])
template = ops_root / "docs/notion/templates/maintenance-report.md"

task = os.environ["MAINT_TASK"]
mode = os.environ["MODE"]
workspaces_root = os.environ["WORKSPACES_ROOT"]
stamp_local = os.environ["STAMP_LOCAL"]
host = os.environ["HOST"]
log_path = os.environ["LOG_PATH"]
json_path = os.environ["JSON_PATH"]
md_path = os.environ["MD_PATH"]
exit_code = int(os.environ["EXIT_CODE"])
output_file = os.environ["OUTPUT_FILE"]

with open(output_file, "r", encoding="utf-8", errors="replace") as f:
    output = f.read()

# Basic summary
if exit_code == 0:
  summary = "Exécution terminée sans erreur."
else:
  summary = f"Exécution terminée avec erreur (exit_code={exit_code}). Voir le log."

# Heuristic details extraction (kept simple)
details_lines = []
for line in output.splitlines():
  if line.startswith("Repo: ") or line.startswith("  - ") or line.startswith("Root: ") or line.startswith("Mode: "):
    details_lines.append(line)

details = "\n".join(details_lines) if details_lines else "(Pas de détails extraits.)"

next_actions = "- Si le mode était dry-run : lancer en mode apply après validation.\n"
if exit_code != 0:
  next_actions += "- Ouvrir le log brut et corriger l’erreur (PATH, droits, dépendances).\n"

text = template.read_text(encoding="utf-8")

repl = {
  "{{TITLE}}": f"{task} ({mode})",
  "{{DATE_LOCAL}}": stamp_local,
  "{{HOST}}": host,
  "{{OPS_TOOLS_PATH}}": str(ops_root),
  "{{WORKSPACES_ROOT}}": workspaces_root,
  "{{MODE}}": mode,
  "{{OPTIONS}}": "normalize-eol-batch standard options",
  "{{SUMMARY}}": summary,
  "{{DETAILS}}": f"```text\n{details}\n```",
  "{{LOG_PATH}}": log_path,
  "{{JSON_PATH}}": json_path,
  "{{NEXT_ACTIONS}}": next_actions,
}

for k, v in repl.items():
  text = text.replace(k, v)

md_path = Path(md_path)
md_path.write_text(text, encoding="utf-8")
print(str(md_path))
PY

# --- Push to Notion database (optional) ---
if [[ -n "${NOTION_API_KEY:-}" && -n "${NOTION_MAINTENANCE_DB_ID:-}" ]]; then
  REPORT_JSON="$JSON_PATH" NOTION_MD_PATH="$MD_PATH" \
  "$PYTHON_BIN" "$OPS_ROOT/scripts/notion/push_report_to_db.py" \
  || echo "Notion DB push failed (non-blocking)"
fi


echo "Log: $LOG_PATH"
echo "JSON: $JSON_PATH"
echo "Notion MD: $MD_PATH"

"$PYTHON_BIN" scripts/maintenance/update-maintenance-index.py || true

exit "$EXIT_CODE"
