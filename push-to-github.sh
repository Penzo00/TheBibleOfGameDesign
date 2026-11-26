#!/usr/bin/env bash
# Universal GitHub publisher for Git Bash (Windows), Linux and macOS.
# Requires Bash 4+, Git and Git LFS.
#
# Workflow:
#   1. Checks branch/remote state and refuses divergent histories.
#   2. Asks before staging and committing all non-ignored working-tree changes.
#   3. Checks staged files against GitHub Pro's Git LFS per-file limit.
#   4. Backs up the local branch before rewriting unpublished history.
#   5. Migrates common ML/scientific/Unreal/creative binary formats and other
#      large files to Git LFS in commits not yet present on the remote.
#   6. Estimates ordinary Git pack size and, for a linear first-parent chain,
#      splits oversized pushes into fast-forward checkpoints.
#   7. Uploads LFS objects, then pushes Git commits. Never force-pushes.
#
# IMPORTANT: Review the files before approving the commit. This script cannot
# decide whether a dataset, credential, model, asset or generated file should
# be published, and it cannot read your GitHub LFS quota/budget.

set -Eeuo pipefail
export LC_ALL=C

# GitHub's individual Git push hard limit is 2 GiB. Keep a margin.
SAFE_PUSH_LIMIT_BYTES="${SAFE_PUSH_LIMIT_BYTES:-1932735283}" # 1.8 GiB
LFS_THRESHOLD="${LFS_THRESHOLD:-50MB}"
LFS_FILE_LIMIT_BYTES="${LFS_FILE_LIMIT_BYTES:-2000000000}" # GitHub Pro LFS file max: 2 GB
DEFAULT_COMMIT_MESSAGE="${COMMIT_MESSAGE:-Update project}"
DEFAULT_REMOTE="${PUSH_REMOTE:-origin}"
PUSH_DELAY_SECONDS="${PUSH_DELAY_SECONDS:-11}" # stay below GitHub's recommended push rate

fail() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

for cmd in git awk wc date grep; do
  require_command "$cmd"
done

[[ "${BASH_VERSINFO[0]}" -ge 4 ]] || fail "Bash 4 or newer is required. On macOS, install a newer Bash (for example via Homebrew)."
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Run this script from inside a Git repository."
git lfs version >/dev/null 2>&1 || fail "Git LFS is not installed. Install it from https://git-lfs.com/ and run 'git lfs install'."

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BRANCH="$(git branch --show-current)"
[[ -n "$BRANCH" ]] || fail "Detached HEAD detected. Check out the branch you intend to publish."

UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
UPSTREAM_REMOTE=""
UPSTREAM_MERGE=""
if [[ -n "$UPSTREAM" ]]; then
  UPSTREAM_REMOTE="$(git config --get "branch.${BRANCH}.remote" || true)"
  UPSTREAM_MERGE="$(git config --get "branch.${BRANCH}.merge" || true)"
  [[ -n "$UPSTREAM_REMOTE" && -n "$UPSTREAM_MERGE" ]] || fail "Could not resolve configured upstream '$UPSTREAM'."
  [[ "$UPSTREAM_REMOTE" != "." ]] || fail "The current branch tracks a local branch, not a GitHub remote. Set PUSH_REMOTE or configure a remote upstream."
fi

# Explicit environment overrides take precedence over the configured upstream.
REMOTE="${PUSH_REMOTE:-${UPSTREAM_REMOTE:-$DEFAULT_REMOTE}}"
if [[ -n "${PUSH_BRANCH:-}" ]]; then
  REMOTE_BRANCH="$PUSH_BRANCH"
elif [[ -n "$UPSTREAM" && "$REMOTE" == "$UPSTREAM_REMOTE" ]]; then
  REMOTE_BRANCH="${UPSTREAM_MERGE#refs/heads/}"
else
  REMOTE_BRANCH="$BRANCH"
fi

git remote get-url "$REMOTE" >/dev/null 2>&1 || fail "Remote '$REMOTE' does not exist. Check 'git remote -v' or set PUSH_REMOTE."
REMOTE_REF="refs/remotes/${REMOTE}/${REMOTE_BRANCH}"

# Refuse to run during an unfinished Git operation.
GIT_DIR="$(git rev-parse --git-dir)"
for state_file in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  [[ ! -f "${GIT_DIR}/${state_file}" ]] || fail "A Git operation is in progress (${state_file}). Finish or abort it first."
done
for state_dir in rebase-merge rebase-apply; do
  [[ ! -d "${GIT_DIR}/${state_dir}" ]] || fail "A rebase is in progress. Finish or abort it first."
done
[[ -z "$(git diff --name-only --diff-filter=U)" ]] || fail "Unresolved merge conflicts are present. Resolve them first."

format_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.2f GiB", bytes / (1024 * 1024 * 1024) }'
}

printf '\nRepository: %s\nBranch: %s\nRemote: %s\nRemote branch: %s\n' \
  "$REPO_ROOT" "$BRANCH" "$REMOTE" "$REMOTE_BRANCH"
printf 'Generic large-file threshold: %s\n' "$LFS_THRESHOLD"
printf 'Git push safety target: %s\n' "$(format_gib "$SAFE_PUSH_LIMIT_BYTES")"
printf '\nGitHub limits to keep in mind:\n'
printf '  - One ordinary Git push: maximum 2 GiB; this script targets 1.8 GiB.\n'
printf '  - Regular Git files: hard rejection above 100 MiB; files over 50 MiB should use LFS.\n'
printf '  - GitHub Pro Git LFS file size: maximum 2 GB per individual file.\n'
printf '  - GitHub Pro included LFS allowance: 10 GiB storage + 10 GiB monthly download bandwidth.\n'
printf '  - The script cannot inspect your account quota, budget or metered overage settings.\n'

printf '\nInitializing Git LFS...\n'
git lfs install

printf '\nFetching remote references...\n'
git fetch --prune "$REMOTE"

# If the remote branch exists but the local fetch refspec did not fetch it,
# explicitly fetch that branch before deciding it is a new remote branch.
if ! git show-ref --verify --quiet "$REMOTE_REF"; then
  REMOTE_SHA="$(git ls-remote --heads "$REMOTE" "refs/heads/${REMOTE_BRANCH}" | awk 'NR == 1 {print $1}')"
  if [[ -n "$REMOTE_SHA" ]]; then
    git fetch "$REMOTE" "refs/heads/${REMOTE_BRANCH}:${REMOTE_REF}"
  fi
fi

HAS_REMOTE_BRANCH=0
REMOTE_BASE_SHA=""
if git show-ref --verify --quiet "$REMOTE_REF"; then
  HAS_REMOTE_BRANCH=1
  REMOTE_BASE_SHA="$(git rev-parse "$REMOTE_REF")"
else
  if [[ -n "$UPSTREAM" ]]; then
    fail "Configured upstream '$UPSTREAM' was not found. Inspect the remote before continuing."
  fi
  printf "Remote branch '%s/%s' does not exist yet; this will be its first push.\n" "$REMOTE" "$REMOTE_BRANCH"
fi

if (( HAS_REMOTE_BRANCH )); then
  if ! git merge-base --is-ancestor "$REMOTE_BASE_SHA" HEAD; then
    if git merge-base --is-ancestor HEAD "$REMOTE_BASE_SHA"; then
      fail "Local branch is behind '$REMOTE/$REMOTE_BRANCH'. Integrate remote changes before publishing."
    fi
    fail "Local branch and '$REMOTE/$REMOTE_BRANCH' have diverged. Resolve the divergence first; this script will not force-push."
  fi
fi

printf '\nCurrent working-tree status:\n'
git status --short
if [[ -n "$(git status --porcelain)" ]]; then
  printf '\nThe script can stage and commit ALL listed, non-ignored changes.\n'
  printf 'Review carefully: ignored files are excluded; all other modifications, deletions and untracked files are included.\n'
  read -r -p "Stage and commit all these changes? [y/N] " COMMIT_ANSWER
  case "$COMMIT_ANSWER" in
    y|Y|yes|YES)
      git add -A
      if ! git diff --cached --quiet; then
        # GitHub Pro's maximum individual Git LFS file size is 2 GB.
        while IFS= read -r -d '' STAGED_FILE; do
          [[ -f "$STAGED_FILE" && ! -L "$STAGED_FILE" ]] || continue
          FILE_BYTES="$(wc -c < "$STAGED_FILE")"
          FILE_BYTES="${FILE_BYTES//[[:space:]]/}"
          [[ "$FILE_BYTES" =~ ^[0-9]+$ ]] || fail "Could not determine size of '$STAGED_FILE'."
          if (( FILE_BYTES >= LFS_FILE_LIMIT_BYTES )); then
            fail "'$STAGED_FILE' is ${FILE_BYTES} bytes. GitHub Pro's LFS per-file limit is 2 GB. Split/shard it or use external object storage before committing."
          fi
        done < <(git diff --cached --name-only --diff-filter=ACMRT -z)

        read -r -p "Commit message [${DEFAULT_COMMIT_MESSAGE}]: " ENTERED_MESSAGE
        COMMIT_MESSAGE="${ENTERED_MESSAGE:-$DEFAULT_COMMIT_MESSAGE}"
        git commit -m "$COMMIT_MESSAGE"
      else
        printf 'No staged changes to commit.\n'
      fi
      ;;
    *)
      fail "Cancelled. Nothing was committed or pushed. Review the working tree and rerun."
      ;;
  esac
fi

git rev-parse --verify HEAD >/dev/null 2>&1 || fail "This repository has no commits yet. Add and commit the initial project files first, then rerun this script."

# Refresh remote state after any new local commit.
git fetch "$REMOTE"
if (( HAS_REMOTE_BRANCH )); then
  REMOTE_BASE_SHA="$(git rev-parse "$REMOTE_REF")"
  git merge-base --is-ancestor "$REMOTE_BASE_SHA" HEAD \
    || fail "Remote branch changed or is no longer an ancestor of local HEAD. No push was attempted."
fi

if (( HAS_REMOTE_BRANCH )); then
  AHEAD_COUNT="$(git rev-list --count "${REMOTE_REF}..HEAD")"
else
  AHEAD_COUNT="$(git rev-list --count HEAD)"
fi
if [[ "$AHEAD_COUNT" -eq 0 ]] && (( HAS_REMOTE_BRANCH )); then
  printf '\nBranch is already up to date with %s/%s. Nothing to push.\n' "$REMOTE" "$REMOTE_BRANCH"
  exit 0
fi

# Save the pre-migration HEAD locally. Never push this recovery branch.
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_BRANCH="backup/${BRANCH//\//-}-before-lfs-${STAMP}"
while git show-ref --verify --quiet "refs/heads/${BACKUP_BRANCH}"; do
  STAMP="${STAMP}-1"
  BACKUP_BRANCH="backup/${BRANCH//\//-}-before-lfs-${STAMP}"
done
git branch "$BACKUP_BRANCH" HEAD
printf '\nCreated local recovery branch: %s\n' "$BACKUP_BRANCH"
printf 'This branch is local only. Keep it until a fresh clone has been verified.\n'

# Patterns mirror the case-insensitive entries in the companion .gitattributes.
# Bracket expressions allow extensions with uppercase characters on Linux too.
LFS_INCLUDE_PATTERNS='*.[oO][nN][nN][xX],*.[nN][pP][zZ],*.[nN][pP][yY],*.[pP][tT],*.[pP][tT][hH],*.[cC][kK][pP][tT],*.[sS][aA][fF][eE][tT][eE][nN][sS][oO][rR][sS],*.[tT][fF][lL][iI][tT][eE],*.[gG][gG][uU][fF],*.[jJ][oO][bB][lL][iI][bB],*.[pP][kK][lL],*.[hH]5,*.[hH][dD][fF]5,*.[kK][eE][rR][aA][sS],*.[pP][bB],*.[pP][aA][rR][qQ][uU][eE][tT],*.[fF][eE][aA][tT][hH][eE][rR],*.[aA][rR][rR][oO][wW],*.[mM][aA][tT],*.[uU][aA][sS][sS][eE][tT],*.[uU][mM][aA][pP],*.[uU][bB][uU][lL][kK],*.[uU][eE][xX][pP],*.[uU][pP][tT][nN][lL],*.[pP][sS][dD],*.[aA][iI],*.[bB][lL][eE][nN][dD],*.[fF][bB][xX],*.[gG][lL][bB],*.[sS][tT][lL],*.[sS][tT][eE][pP],*.[sS][tT][pP],*.[3][mM][fF],*.[wW][aA][vV],*.[mM][pP]3,*.[fF][lL][aA][cC],*.[oO][gG][gG],*.[mM][pP]4,*.[mM][oO][vV],*.[mM][kK][vV],*.[aA][vV][iI],*.[wW][eE][bB][mM],*.[zZ][iI][pP],*.[7][zZ],*.[rR][aA][rR]'

printf '\nLarge-file summary before migration (unpublished history):\n'
git lfs migrate info --above="$LFS_THRESHOLD" --top=25

printf '\nMigrating common model/data/Unreal/creative formats to Git LFS...\n'
git lfs migrate import --include="$LFS_INCLUDE_PATTERNS" --verbose

printf '\nMigrating any other file larger than %s to Git LFS...\n' "$LFS_THRESHOLD"
git lfs migrate import --above="$LFS_THRESHOLD" --verbose

printf '\nApplying existing .gitattributes rules to unpublished commits...\n'
git lfs migrate import --fixup --verbose

[[ -z "$(git status --porcelain)" ]] || fail "Working tree is not clean after LFS migration. Inspect 'git status'. Recovery branch: $BACKUP_BRANCH"

# Estimate the ordinary Git pack. LFS payloads are uploaded by `git lfs push`,
# separately from the ordinary Git pack.
estimate_pack_bytes() {
  local candidate="$1"
  local extra_base="${2:-}"
  local raw
  raw="$({
    printf '%s\n' "$candidate"
    git for-each-ref --format='^%(refname)' "refs/remotes/${REMOTE}/"
    if [[ -n "$extra_base" ]]; then
      printf '^%s\n' "$extra_base"
    fi
  } | git pack-objects --stdout --revs --thin | wc -c)" \
    || fail "Could not estimate the outgoing Git pack."
  raw="${raw//[[:space:]]/}"
  [[ "$raw" =~ ^[0-9]+$ ]] || fail "Could not parse outgoing Git pack size: '$raw'."
  printf '%s' "$raw"
}

PLAN_COMMITS=()
PLAN_SIZES=()
WHOLE_PACK_BYTES="$(estimate_pack_bytes HEAD "")"
printf '\nEstimated Git pack for the complete push: %s\n' "$(format_gib "$WHOLE_PACK_BYTES")"

if (( WHOLE_PACK_BYTES <= SAFE_PUSH_LIMIT_BYTES )); then
  PLAN_COMMITS=("$(git rev-parse HEAD)")
  PLAN_SIZES=("$WHOLE_PACK_BYTES")
else
  printf '\nComplete Git pack exceeds the safety target. Planning smaller fast-forward pushes...\n'

  if (( HAS_REMOTE_BRANCH )); then
    if ! git rev-list --first-parent HEAD | grep -Fqx "$REMOTE_BASE_SHA"; then
      fail "Remote tip is not on the local first-parent chain. Cannot safely batch this history automatically. Lower LFS_THRESHOLD or split/rebase the unpublished history manually."
    fi
    mapfile -t CANDIDATE_COMMITS < <(git rev-list --first-parent --reverse "${REMOTE_REF}..HEAD")
    PLAN_BASE="$REMOTE_BASE_SHA"
  else
    mapfile -t CANDIDATE_COMMITS < <(git rev-list --first-parent --reverse HEAD)
    PLAN_BASE=""
  fi

  LAST_FIT=""
  LAST_FIT_SIZE=""
  for CANDIDATE in "${CANDIDATE_COMMITS[@]}"; do
    [[ -n "$CANDIDATE" ]] || continue
    CANDIDATE_SIZE="$(estimate_pack_bytes "$CANDIDATE" "$PLAN_BASE")"

    if (( CANDIDATE_SIZE <= SAFE_PUSH_LIMIT_BYTES )); then
      LAST_FIT="$CANDIDATE"
      LAST_FIT_SIZE="$CANDIDATE_SIZE"
      continue
    fi

    if [[ -z "$LAST_FIT" ]]; then
      fail "A single first-parent commit requires $(format_gib "$CANDIDATE_SIZE"), above the 1.8 GiB safety target. Lower LFS_THRESHOLD (for example, LFS_THRESHOLD=10MB bash ./push-to-github.sh) or split that commit manually. No push was attempted."
    fi

    PLAN_COMMITS+=("$LAST_FIT")
    PLAN_SIZES+=("$LAST_FIT_SIZE")
    PLAN_BASE="$LAST_FIT"
    LAST_FIT=""
    LAST_FIT_SIZE=""

    CANDIDATE_SIZE="$(estimate_pack_bytes "$CANDIDATE" "$PLAN_BASE")"
    if (( CANDIDATE_SIZE > SAFE_PUSH_LIMIT_BYTES )); then
      fail "Commit ${CANDIDATE:0:12} introduces $(format_gib "$CANDIDATE_SIZE") of objects by itself. Lower LFS_THRESHOLD or split the commit manually. No further push was attempted."
    fi
    LAST_FIT="$CANDIDATE"
    LAST_FIT_SIZE="$CANDIDATE_SIZE"
  done

  if [[ -n "$LAST_FIT" ]]; then
    PLAN_COMMITS+=("$LAST_FIT")
    PLAN_SIZES+=("$LAST_FIT_SIZE")
  fi
  [[ "${#PLAN_COMMITS[@]}" -gt 0 ]] || fail "Could not construct a safe push plan. No push was attempted."
fi

printf '\nPlanned GitHub push sequence:\n'
for i in "${!PLAN_COMMITS[@]}"; do
  printf '  %d. %s  approximately %s\n' \
    "$((i + 1))" "${PLAN_COMMITS[$i]:0:12}" "$(format_gib "${PLAN_SIZES[$i]}")"
done
printf '\nEach individual ordinary Git push is estimated below 1.8 GiB.\n'
printf 'Git LFS payloads are uploaded separately and are subject to LFS file-size and account quota limits.\n'

read -r -p "Upload LFS objects and push ${#PLAN_COMMITS[@]} fast-forward step(s) to ${REMOTE}/${REMOTE_BRANCH}? [y/N] " PUSH_ANSWER
case "$PUSH_ANSWER" in
  y|Y|yes|YES) ;;
  *) fail "Cancelled before upload. Migrated commits and the recovery branch remain local." ;;
esac

printf '\nUploading Git LFS objects...\n'
git lfs push "$REMOTE" "$BRANCH"

printf '\nPushing Git branch checkpoint(s)...\n'
for i in "${!PLAN_COMMITS[@]}"; do
  CHECKPOINT="${PLAN_COMMITS[$i]}"
  git push -u "$REMOTE" "${CHECKPOINT}:refs/heads/${REMOTE_BRANCH}"
  # Update the tracking ref only after GitHub confirms this checkpoint.
  git update-ref "$REMOTE_REF" "$CHECKPOINT"
  if (( i + 1 < ${#PLAN_COMMITS[@]} )); then
    sleep "$PUSH_DELAY_SECONDS"
  fi
done

printf '\nRefreshing remote references...\n'
git fetch --prune "$REMOTE"
printf '\nPush completed. Final status:\n'
git status -sb
printf '\nLocal recovery branch retained: %s\n' "$BACKUP_BRANCH"
printf 'Keep it until the GitHub repository and a fresh clone have been verified.\n'
printf 'Review GitHub Settings > Billing and licensing > Metered usage for LFS storage/bandwidth.\n'
