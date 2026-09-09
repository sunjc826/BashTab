#!/usr/bin/env bash
# Pipeline: producer
# Fields: remote ref status before after
# Dispatch: source
# Synopsis: Fetch and integrate remote Git changes
function __bu_bu_pull_git_ref_main()
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

local remote=origin
local ref=
local is_rebase=false
local is_ff_only=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --remote)# REMOTE
        # Remote name (default: origin)
        bu_parse_positional $# --hint "Remote name"
        remote=${!shift_by}
        ;;
    --ref)# REF
        # Branch to pull (default: current branch's upstream)
        bu_parse_positional $# --hint "Branch name"
        ref=${!shift_by}
        ;;
    -r|--rebase)# _FLAG
        # Rebase local commits on top of pulled commits (git pull --rebase)
        is_rebase=true
        ;;
    --ff-only)# _FLAG
        # Only fast-forward (abort if merge is needed)
        is_ff_only=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be pulled without doing it
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
Pull changes from a remote (git pull).

Emits a JSONL record with the remote, branch, and result status.

Output record fields: remote, ref, status, before, after
" \
        --example "Pull current branch" "" \
        --example "Rebase pull" "--rebase" \
        --example "Fast-forward only" "--ff-only" \
        --example "Specific remote/branch" "--remote upstream --ref main"
    return 0
fi

# Record HEAD before pull
local before
before=$(git rev-parse --short HEAD 2>/dev/null) || true

if "$is_dry_run"; then
    bu_out_record remote="$remote" ref="${ref:-upstream}" status="dry-run" before="$before" | bu_out --format jsonl
    local -a cmd=(git fetch --dry-run "$remote")
    [[ -n "$ref" ]] && cmd+=("$ref")
    "${cmd[@]}" 2>&1 || true
    bu_scope_pop_function
    return 0
fi

local -a cmd=(git pull)
"$is_rebase" && cmd+=(--rebase)
"$is_ff_only" && cmd+=(--ff-only)
cmd+=("$remote")
[[ -n "$ref" ]] && cmd+=("$ref")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

local output
output=$("${cmd[@]}" 2>&1) || {
    # git pull can exit non-zero for "already up to date" or real errors
    if [[ "$output" == *"Already up to date"* ]] || [[ "$output" == *"already up to date"* ]]; then
        local after
        after=$(git rev-parse --short HEAD 2>/dev/null) || true
        bu_out_record remote="$remote" ref="${ref:-}" status="up-to-date" before="$before" after="$after" | bu_out --format jsonl
        bu_scope_pop_function
        return 0
    fi
    error_msg="$output"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

local after
after=$(git rev-parse --short HEAD 2>/dev/null) || true
bu_out_record remote="$remote" ref="${ref:-}" status="pulled" before="$before" after="$after" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_pull_git_ref_main "$@"
