#!/usr/bin/env bash
# BashTab release tool — cut a datetime-based (CalVer) release.
#
# Usage:
#   ./release.sh [options]
#
# Options:
#   --dry-run   Compute and print the next tag without creating anything.
#               The tag is printed to stdout (for scripting); all other
#               output goes to stderr.
#   --yes       Skip the interactive confirmation prompt.
#   --no-push   Create the tag locally but do not push to the remote.
#   --no-gh     Do not create a GitHub Release (even if `gh` is installed).
#   --force     Bypass the clean-worktree / on-main safety checks.
#   -h|--help   Show this help.
#
# Tag scheme (UTC):
#   vYYYY.MM.DD        first release of a UTC day
#   vYYYY.MM.DD.N      Nth *additional* release of the day, where N is the
#                      highest existing suffix + 1
#                      (e.g. v2026.08.14.1 is the second release on 2026-08-14)
#
# The tag is never chosen by hand — it is derived from the current UTC date
# plus any same-day releases that already exist. This removes the arbitrary
# semver bump that manual tagging required. Tags are annotated, monotonic,
# and sort correctly with `sort -V` and `git tag --sort=v:refname`.
set -euo pipefail

: "${MAIN_BRANCH:=main}"

# bash-ide parse-func-sig
log()  { printf '%s\n' "$*" >&2; }
# bash-ide parse-func-sig
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# bash-ide parse-func-sig
usage() {
    awk 'NR==1{next} /^set -euo pipefail$/{exit} {sub(/^# ?/, ""); print}' "${BASH_SOURCE[0]}"
}

# Resolve the repository root. The release script lives at the repo root,
# so its own directory *is* the root (mirrors bu_entrypoint.sh's convention).
# bash-ide parse-func-sig
repo_root() {
    local src=${BASH_SOURCE[0]}
    local dir
    case "$src" in
    */*) dir=${src%/*} ;;
    *)   dir=. ;;
    esac
    cd "$dir"
    pwd
}

git_ref_exists() {
    git rev-parse -q --verify "$1" >/dev/null 2>&1
}

# Print the next release tag on stdout.
#
# Returns:
# - stdout: the next tag, e.g. "v2026.08.15" or "v2026.08.15.2"
# bash-ide parse-func-sig
compute_next_tag() {
    local today base
    today=$(date -u +%Y.%m.%d)
    base="v${today}"

    if ! git_ref_exists "refs/tags/${base}"; then
        printf '%s\n' "$base"
        return 0
    fi

    # One or more releases already today. The next suffix is the current
    # maximum suffix + 1 (max-based, so a manually-deleted intermediate
    # tag can never cause a collision or a backward bump).
    local max=0 tag n
    while IFS= read -r tag; do
        [[ -z "$tag" ]] && continue
        n=${tag##*.}
        [[ "$n" =~ ^[0-9]+$ ]] || continue
        if (( n > max )); then
            max=$n
        fi
    done < <(git tag -l "${base}.*")

    printf '%s.%d\n' "$base" "$(( max + 1 ))"
}

main() {
    local dry_run=false yes=false no_push=false no_gh=false force=false
    while (($#)); do
        case "$1" in
        --dry-run) dry_run=true ;;
        --yes)     yes=true ;;
        --no-push) no_push=true ;;
        --no-gh)   no_gh=true ;;
        --force)   force=true ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
        esac
        shift
    done

    ROOT=$(repo_root)
    cd "$ROOT"

    command -v git >/dev/null 2>&1 || die "git not found"

    # Safety checks (bypassable with --force for edge cases like CI).
    # Dry-run is non-mutating, so it skips these to preview the tag anywhere.
    if ! "$dry_run" && ! "$force"; then
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            die "Working tree is dirty. Commit or stash, or pass --force."
        fi
        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || true)
        if [[ "$branch" != "$MAIN_BRANCH" ]]; then
            die "Not on $MAIN_BRANCH (current: ${branch:-detached}). Pass --force to tag anyway."
        fi
    fi

    # Previous release tag (topologically nearest to HEAD).
    local prev
    prev=$(git describe --tags --abbrev=0 2>/dev/null || true)

    local commit_count=0
    if [[ -n "$prev" ]]; then
        commit_count=$(git rev-list --count "${prev}..HEAD" 2>/dev/null || echo 0)
    else
        commit_count=$(git rev-list --count HEAD 2>/dev/null || echo 0)
    fi
    if [[ "$commit_count" == "0" ]]; then
        log "Nothing to release: no commits since ${prev:-the first commit}."
        exit 0
    fi

    local tag
    tag=$(compute_next_tag)

    local changes
    if [[ -n "$prev" ]]; then
        changes=$(git log --no-merges --pretty=format:'  %s' "${prev}..HEAD")
    else
        changes=$(git log --no-merges --pretty=format:'  %s')
    fi
    [[ -z "$changes" ]] && changes="  (no conventional commits; see full history)"

    log "Next release: ${tag}"
    log "  Previous tag : ${prev:-<none>}"
    log "  New commits  : ${commit_count}"
    log "  HEAD         : $(git log -1 --pretty=format:'%h %s')"

    if "$dry_run"; then
        printf '%s\n' "$tag"
        return 0
    fi

    if ! "$yes"; then
        local ans
        read -r -p "Create and push ${tag}? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
    fi

    local msg
    msg="Release ${tag}

Changes since ${prev:-the beginning}:
${changes}"

    git tag -a "$tag" -m "$msg"

    if ! "$no_push"; then
        git push origin "$(git symbolic-ref --short HEAD 2>/dev/null || echo HEAD)" "$tag"
    fi

    if ! "$no_push" && ! "$no_gh"; then
        if command -v gh >/dev/null 2>&1; then
            gh release create "$tag" --generate-notes --title "$tag" \
                || log "WARN: gh release create failed (tag was already pushed)."
        else
            log "NOTE: gh not found — skipping GitHub Release."
        fi
    fi

    log "Released ${tag}"
}

main "$@"
