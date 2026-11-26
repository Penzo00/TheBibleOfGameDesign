#!/usr/bin/env bash
# Fetch and browse the official github/gitignore template catalogue.
# Templates are not concatenated automatically: choose only those relevant
# to the repository so that useful project files are not accidentally ignored.
#
# Usage:
#   bash ./sync-github-gitignore-templates.sh
#   bash ./sync-github-gitignore-templates.sh --list
#   bash ./sync-github-gitignore-templates.sh --search Python
#   bash ./sync-github-gitignore-templates.sh --show Python.gitignore
#   bash ./sync-github-gitignore-templates.sh --append Python.gitignore
#   GITHUB_GITIGNORE_CACHE=/path/to/cache bash ./sync-github-gitignore-templates.sh --list

set -Eeuo pipefail

REPO_URL="https://github.com/github/gitignore.git"
DEFAULT_CACHE="${XDG_CACHE_HOME:-${HOME:-$PWD}/.cache}/github-gitignore-templates"
CACHE_DIR="${GITHUB_GITIGNORE_CACHE:-$DEFAULT_CACHE}"
ACTION="${1:---help}"
ARG="${2:-}"

usage() {
  cat <<'USAGE'
Official GitHub .gitignore template manager

Commands:
  --list                 List all downloaded *.gitignore templates.
  --search TERM          Search template paths by name.
  --show TEMPLATE_PATH   Print a template (e.g. Python.gitignore).
  --append TEMPLATE_PATH Append one selected template to this repo's .gitignore.
  --help                 Show this help.

Optional cache location:
  GITHUB_GITIGNORE_CACHE=/path/to/cache

Examples:
  bash ./sync-github-gitignore-templates.sh --list
  bash ./sync-github-gitignore-templates.sh --search Unreal
  bash ./sync-github-gitignore-templates.sh --show Global/VisualStudioCode.gitignore
  bash ./sync-github-gitignore-templates.sh --append Python.gitignore

The official catalogue has root templates, Global templates, and community
specialized templates. Select only templates relevant to this project.
USAGE
}

command -v git >/dev/null 2>&1 || { echo "ERROR: git is required." >&2; exit 1; }

# Sync the source catalogue before listing, viewing or appending templates.
if [[ -d "$CACHE_DIR/.git" ]]; then
  ORIGIN_URL="$(git -C "$CACHE_DIR" remote get-url origin 2>/dev/null || true)"
  case "$ORIGIN_URL" in
    https://github.com/github/gitignore.git|https://github.com/github/gitignore|git@github.com:github/gitignore.git) ;;
    *) echo "ERROR: Cache directory is a Git repository but its origin is not the official github/gitignore repository: $ORIGIN_URL" >&2; exit 1 ;;
  esac
  echo "Updating official GitHub .gitignore templates..."
  git -C "$CACHE_DIR" pull --ff-only
elif [[ -e "$CACHE_DIR" ]]; then
  echo "ERROR: Cache path exists but is not a clone of github/gitignore: $CACHE_DIR" >&2
  echo "Choose another path with GITHUB_GITIGNORE_CACHE." >&2
  exit 1
else
  mkdir -p "$(dirname "$CACHE_DIR")"
  echo "Cloning official GitHub .gitignore templates..."
  git clone --depth 1 "$REPO_URL" "$CACHE_DIR"
fi

list_templates() {
  find "$CACHE_DIR" -type f -name '*.gitignore' -not -path '*/.git/*' \
    | sed "s#^${CACHE_DIR}/##" \
    | LC_ALL=C sort
}

resolve_template() {
  local relative="$1"
  [[ -n "$relative" ]] || { echo "ERROR: Specify a template path." >&2; exit 2; }
  [[ "$relative" != /* && "$relative" != *".."* && "$relative" != *"\\"* ]] \
    || { echo "ERROR: Use a safe repository-relative template path." >&2; exit 2; }
  local path="$CACHE_DIR/$relative"
  [[ -f "$path" ]] || { echo "ERROR: Template not found: $relative" >&2; echo "Use --list or --search to find a template." >&2; exit 2; }
  printf '%s' "$path"
}

case "$ACTION" in
  --help|-h|help)
    usage
    ;;
  --list)
    list_templates
    ;;
  --search)
    [[ -n "$ARG" ]] || { echo "ERROR: Provide a search term." >&2; exit 2; }
    list_templates | grep -i -- "$ARG" || true
    ;;
  --show)
    TEMPLATE_PATH="$(resolve_template "$ARG")"
    cat "$TEMPLATE_PATH"
    ;;
  --append)
    TEMPLATE_PATH="$(resolve_template "$ARG")"
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
      || { echo "ERROR: Run --append from inside the target Git repository." >&2; exit 1; }
    TARGET_GITIGNORE="$REPO_ROOT/.gitignore"
    MARKER="# BEGIN official GitHub template: $ARG"
    if [[ -f "$TARGET_GITIGNORE" ]] && grep -Fqx "$MARKER" "$TARGET_GITIGNORE"; then
      echo "Template already appears to be appended: $ARG"
      exit 0
    fi
    {
      printf '\n\n%s\n' "$MARKER"
      printf '# Source: https://github.com/github/gitignore/blob/main/%s\n\n' "$ARG"
      cat "$TEMPLATE_PATH"
      printf '\n# END official GitHub template: %s\n' "$ARG"
    } >> "$TARGET_GITIGNORE"
    printf 'Appended %s to %s\n' "$ARG" "$TARGET_GITIGNORE"
    printf 'Review the new rules before committing; remove any rule that would hide required files.\n'
    ;;
  *)
    echo "ERROR: Unknown command: $ACTION" >&2
    usage >&2
    exit 2
    ;;
esac
