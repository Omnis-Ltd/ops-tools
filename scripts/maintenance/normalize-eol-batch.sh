#!/usr/bin/env bash
set -euo pipefail

ROOT="${WORKSPACES_ROOT:-$HOME/git/Workspaces}"

MODE="dry-run"          # dry-run | apply
DO_RENORMALIZE="no"     # yes | no
DO_COMMIT="no"          # yes | no
SKIP_DIRTY="no"         # yes | no

shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) MODE="apply" ;;
    --dry-run) MODE="dry-run" ;;
    --renormalize) DO_RENORMALIZE="yes" ;;
    --commit) DO_COMMIT="yes" ;;
    --skip-dirty) SKIP_DIRTY="yes" ;;
    --help)
      cat <<'EOF'
Usage:
  ./normalize-eol-batch.sh [ROOT] [--dry-run|--apply] [--renormalize] [--commit] [--skip-dirty]

Defaults:
  ROOT=~/git/Workspaces
  --dry-run

Examples:
  ./normalize-eol-batch.sh --dry-run
  ./normalize-eol-batch.sh --apply
  ./normalize-eol-batch.sh --apply --renormalize
  ./normalize-eol-batch.sh --apply --renormalize --commit --skip-dirty
EOF
      exit 0
      ;;
    *)
      echo "Option inconnue: $1" >&2
      exit 2
      ;;
  esac
  shift
done

ATTR_CONTENT=$'* text=auto eol=lf\n\n*.md   text eol=lf\n*.json text eol=lf\n*.yml  text eol=lf\n*.yaml text eol=lf\n*.sh   text eol=lf\n*.py   text eol=lf\n*.js   text eol=lf\n*.ts   text eol=lf\n*.css  text eol=lf\n*.html text eol=lf\n'

EDITORCONFIG_CONTENT=$'root = true\n\n[*]\ncharset = utf-8\nend_of_line = lf\ninsert_final_newline = true\nindent_style = space\nindent_size = 2\n\n[*.md]\ntrim_trailing_whitespace = false\n\n[*.json]\nindent_size = 2\n'

echo "Root: $ROOT"
echo "Mode: $MODE | renormalize: $DO_RENORMALIZE | commit: $DO_COMMIT | skip-dirty: $SKIP_DIRTY"
echo

if [[ ! -d "$ROOT" ]]; then
  echo "Erreur: ROOT introuvable: $ROOT" >&2
  exit 1
fi

# Liste des repos = dossiers contenant .git (non bare)
mapfile -t REPOS < <(find "$ROOT" -type d -name ".git" -prune 2>/dev/null | sed 's|/\.git$||' | sort)

if [[ ${#REPOS[@]} -eq 0 ]]; then
  echo "Aucun repo git détecté sous: $ROOT"
  exit 0
fi

write_if_changed() {
  local path="$1"
  local content="$2"

  if [[ -f "$path" ]]; then
    # compare contenu
    if cmp -s <(printf "%s" "$content") "$path"; then
      echo "    - OK (déjà conforme): $(basename "$path")"
      return 0
    else
      echo "    - UPDATE: $(basename "$path")"
      if [[ "$MODE" == "apply" ]]; then
        printf "%s" "$content" > "$path"
      fi
      return 0
    fi
  else
    echo "    - CREATE: $(basename "$path")"
    if [[ "$MODE" == "apply" ]]; then
      printf "%s" "$content" > "$path"
    fi
    return 0
  fi
}

repo_is_dirty() {
  local repo="$1"
  (cd "$repo" && ! git diff --quiet || ! git diff --cached --quiet || [[ -n "$(git status --porcelain)" ]])
}

for repo in "${REPOS[@]}"; do
  echo "Repo: $repo"
  if [[ ! -d "$repo/.git" ]]; then
    echo "  - SKIP: .git manquant (repo non standard?)"
    echo
    continue
  fi

  if [[ "$SKIP_DIRTY" == "yes" ]]; then
    if repo_is_dirty "$repo"; then
      echo "  - SKIP: repo dirty (modifs non commit)"
      echo
      continue
    fi
  fi

  # écriture fichiers
  echo "  - Plan:"
  echo "    - Ensure .gitattributes + .editorconfig (LF)"
  if [[ "$DO_RENORMALIZE" == "yes" ]]; then
    echo "    - git add --renormalize ."
  fi
  if [[ "$DO_COMMIT" == "yes" ]]; then
    echo "    - commit si changements"
  fi

  if [[ "$MODE" == "apply" ]]; then
    # small safety: verify it's a git worktree
    (cd "$repo" && git rev-parse --is-inside-work-tree >/dev/null)
  fi

  echo "  - Actions:"
  write_if_changed "$repo/.gitattributes" "$ATTR_CONTENT"
  write_if_changed "$repo/.editorconfig" "$EDITORCONFIG_CONTENT"

  if [[ "$MODE" == "apply" ]]; then
    if [[ "$DO_RENORMALIZE" == "yes" ]]; then
      (cd "$repo" && git add --renormalize .)
      echo "    - DONE: renormalize"
    fi

    # show summary of changes
    if (cd "$repo" && ! git diff --quiet); then
      echo "    - DIFF: modifications détectées"
      if [[ "$DO_COMMIT" == "yes" ]]; then
        # commit only if there are staged or unstaged changes
        (cd "$repo" && git add .gitattributes .editorconfig || true)
        # If renormalize staged a bunch, keep it staged.
        if (cd "$repo" && ! git diff --cached --quiet); then
          (cd "$repo" && git commit -m "chore: normalize line endings (LF)" )
          echo "    - COMMIT: effectué"
        else
          echo "    - COMMIT: rien à committer (index inchangé)"
        fi
      else
        echo "    - NOTE: pas de commit (mode sans --commit)"
      fi
    else
      echo "    - OK: aucun changement détecté"
    fi
  else
    echo "  - DRY-RUN: aucune écriture/commande git exécutée"
  fi

  echo
done

echo "Terminé."
if [[ "$MODE" == "dry-run" ]]; then
  echo "Pour appliquer: ./normalize-eol-batch.sh \"$ROOT\" --apply --renormalize --commit --skip-dirty"
fi
