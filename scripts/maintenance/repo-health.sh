#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-$HOME/git/Workspaces}"

if [[ ! -d "$ROOT" ]]; then
  echo "Erreur: ROOT introuvable: $ROOT" >&2
  exit 1
fi

mapfile -t REPOS < <(find "$ROOT" -type d -name ".git" -prune | sed 's|/\.git$||' | sort)

echo "Repos détectés: ${#REPOS[@]}"
echo

for repo in "${REPOS[@]}"; do
  echo "Repo: $repo"
  (cd "$repo" && {
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    dirty="$(git status --porcelain | wc -l | tr -d ' ')"
    echo "  branch: $branch | dirty entries: $dirty"
  })
 # echo "$REPO_SLUG" >> "$REPOS_LIST_PATH"
done
