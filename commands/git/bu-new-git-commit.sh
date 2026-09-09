#!/usr/bin/env bash
# Pipeline: producer
# Fields: commit message amended
# Dispatch: source
# Synopsis: Create a new Git commit
function __bu_bu_new_git_commit_main()
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

local message=
local is_amend=false
local is_allow_empty=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -m|--message)# MESSAGE
        # Commit message (required)
        bu_parse_positional $# --hint "Commit message"
        message=${!shift_by}
        ;;
    --amend)# _FLAG
        # Amend the previous commit instead of creating a new one
        is_amend=true
        ;;
    --allow-empty)# _FLAG
        # Allow an empty commit (no staged changes)
        is_allow_empty=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be committed without doing it
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        is_help=true
        ;;
    --)
        shift
        break
        ;;
    *)
        break
        ;;
    esac
    if "$is_help"; then break; fi
    if (( $# < shift_by )); then bu_parse_error_argn "$1" $#; break; fi
    shift "$shift_by"
done
local remaining_options=("$@")
if bu_env_is_in_autocomplete; then bu_autocomplete; return 0; fi

if "$is_help"; then
    bu_autohelp \
        --description "
Create a new commit with staged changes (git commit).

Emits a JSONL record with the new commit hash, message, and whether it was an
amend. If nothing is staged and --allow-empty is not set, fails with an error.
Use --amend to fold changes into the previous commit.

Output record fields: commit, message, amended (bool)
" \
        --example "Simple commit" "--message 'Fix off-by-one error'" \
        --example "Amend previous" "--amend --message 'Fix off-by-one (v2)'" \
        --example "Dry run" "--message 'test' --dry-run"
    return 0
fi

if [[ -z "$message" ]] && ! "$is_amend"; then
    error_msg="--message is required (e.g. bu new-git-commit --message 'Fix bug')"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local -a cmd=(git commit)
[[ -n "$message" ]] && cmd+=(-m "$message")
"$is_amend" && cmd+=(--amend)
"$is_allow_empty" && cmd+=(--allow-empty)
"$is_dry_run" && cmd+=(--dry-run)
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

local output
output=$("${cmd[@]}" 2>&1) || {
    # git commit exits non-zero if nothing to commit (not a real error in dry-run)
    if "$is_dry_run"; then
        echo "$output" >&2
    else
        error_msg="$output"
        bu_autohelp
        bu_scope_pop_function
        return 1
    fi
}

# Emit the resulting commit hash
if ! "$is_dry_run"; then
    local commit
    commit=$(git rev-parse HEAD 2>/dev/null) || true
    if [[ -n "$commit" ]]; then
        bu_out_record commit="$commit" message:="$message" amended:="$is_amend" | bu_out --format jsonl
    fi
fi

bu_scope_pop_function
}

__bu_bu_new_git_commit_main "$@"
