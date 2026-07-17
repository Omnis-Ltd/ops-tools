#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-$HOME/.config/env/notion.env}"

if [[ -f "$ENV_FILE" ]]; then
  # export automatique de toutes les variables définies dans le fichier
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

exec "$@"

