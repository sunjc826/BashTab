#!/usr/bin/env bash
# Pipeline: consume
# Requires-All: path
# Dispatch: source
# Synopsis: Stage file changes for the next Git commit
function __bu_bu_add_git_file_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
if [[ "$1" == "--is-compatible" ]]; then
    command -v git &>/dev/null || { echo "git is required" >&2; exit 1; }
    git rev-parse --git-dir &>/dev/null || { echo "not inside a git repository" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local is_all=false
local is_update=false
local is_patch=false
local is_dry_run=false
local is_verbose=false
local -a paths=()
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -a|--all)# _FLAG
        # Stage all tracked, modified files (git add -u)
        is_all=true
        ;;
    -u|--update)# _FLAG
        # Stage modifications and deletions, but not new files (git add -u)
        is_update=true
        ;;
    -p|--patch)# _FLAG
        # Interactively choose hunks to stage (git add -p)
        is_patch=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be staged without actually staging
        is_dry_run=true
        ;;
    --verbose)# _FLAG
        # Show detailed output from git add
        is_verbose=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete; then
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        paths+=("$1")
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "
Stage files for commit (git add).

Accepts file paths as positional arguments. When no paths are given and stdin
is a pipe, reads JSONL records from stdin and stages the file named in each
record's .path field. This enables composability:

  bu get-git-status | bu where '.staged == \"?\"' | bu add-git-file

Flags:
  --all        Stage all tracked, modified files (git add -u for tracked only)
  --update     Stage modifications and deletions only, skip untracked (git add -u)
  --patch      Interactively stage hunks
  --dry-run    Show what would be staged without doing it
" \
        --example "Stage specific files" "src/main.c include/header.h" \
        --example "Stage all changes" "--all" \
        --example "Stage from pipeline" "(echo from get-git-status pipe...)" \
        --example "Dry-run" "--all --dry-run"
    return 0
fi

# Read paths from stdin pipeline if no positional paths and stdin has data
if ((${#paths[@]} == 0)) && read -t 0 2>/dev/null; then
    local line
    while IFS= read -r line; do
        local p
        p=$(jq -r '.path // empty' <<<"$line" 2>/dev/null) || true
        [[ -n "$p" ]] && paths+=("$p")
    done < <(__bu_out_strict_guard "add-git-file")
fi

if ((${#paths[@]} == 0)) && ! "$is_all" && ! "$is_update"; then
    error_msg="No files specified. Provide paths, --all, --update, or pipe records with .path fields."
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a cmd=(git add)
"$is_all" && cmd=(git add -A)
"$is_update" && cmd=(git add -u)
"$is_patch" && cmd+=(--patch)
"$is_dry_run" && cmd+=(--dry-run)
"$is_verbose" && cmd+=(--verbose)
if ((${#paths[@]} > 0)); then cmd+=("${paths[@]}"); fi

if "$is_dry_run" || "$is_verbose"; then
    "${cmd[@]}"
else
    "${cmd[@]}" 2>/dev/null
fi

# Emit staged files as records for pipeline continuation
if ! "$is_dry_run"; then
    local -a staged=()
    if "$is_all" || "$is_update"; then
        mapfile -t staged < <(git diff --cached --name-only 2>/dev/null)
    else
        staged=("${paths[@]}")
    fi
    local f
    for f in "${staged[@]}"; do
        bu_out_record path="$f" staged:=true
    done | bu_out --format jsonl
fi

bu_scope_pop_function
}

__bu_bu_add_git_file_main "$@"
