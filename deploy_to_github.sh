#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="https://github.com/Davud77/BotPlus-PDF-Editor.git"
COMMIT_MESSAGE="feat: initial release of BotPlus PDF Editor for macOS"
PUSH=false
CREATE_REMOTE=false

usage() {
  cat <<'EOF'
Usage: ./deploy_to_github.sh [--push] [--create-remote] [--help]

Initializes this project as a local Git repository, stages and commits its files,
sets origin to Davud77/BotPlus-PDF-Editor, and names the default branch main.
Pass --push to publish the branch to the configured GitHub repository.
Pass --create-remote to create the GitHub repository with gh before pushing.
EOF
}

for argument in "$@"; do
  case "$argument" in
    --push) PUSH=true ;;
    --create-remote) CREATE_REMOTE=true; PUSH=true ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$argument" >&2; usage >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TOP_LEVEL="$(git rev-parse --show-toplevel)"
  if [[ "$TOP_LEVEL" != "$PROJECT_ROOT" ]]; then
    printf 'Refusing to modify parent repository at %s. Run this script from its own Git root.\n' "$TOP_LEVEL" >&2
    exit 1
  fi
else
  git init --initial-branch=main
fi

if git rev-parse --verify HEAD >/dev/null 2>&1; then
  git branch -M main
else
  git symbolic-ref HEAD refs/heads/main
fi
if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPOSITORY_URL"
else
  git remote add origin "$REPOSITORY_URL"
fi

git add --all
if git diff --cached --quiet; then
  printf 'No staged changes to commit.\n'
else
  git commit -m "$COMMIT_MESSAGE"
fi

if [[ "$PUSH" == true ]]; then
  if [[ "$CREATE_REMOTE" == true ]]; then
    if ! command -v gh >/dev/null 2>&1; then
      printf '%s\n' '--create-remote requires GitHub CLI (gh). Install it and run gh auth login first.' >&2
      exit 1
    fi
    gh repo create Davud77/BotPlus-PDF-Editor
  fi
  git push --set-upstream origin main
else
  printf 'Local commit is ready. Review the repository, then run ./deploy_to_github.sh --push to publish it.\n'
fi
