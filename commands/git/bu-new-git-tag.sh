#!/usr/bin/env bash
# Pipeline: producer
# Fields: name commit type status
# Dispatch: source
# Synopsis: Create a new Git tag
function __bu_bu_new_git_tag_main()
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

local name=
local message=
local ref=HEAD
local is_annotated=false
local is_force=false
local is_dry_run=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --name)# NAME
        # Tag name (required)
        bu_parse_positional $# --hint "Tag name"
        name=${!shift_by}
        ;;
    -m|--message)# MESSAGE
        # Tag message. Makes this an annotated tag if not using --annotated.
        bu_parse_positional $# --hint "Tag message"
        message=${!shift_by}
        ;;
    --ref)# REF
        # Commit/branch to tag (default: HEAD)
        bu_parse_positional $# --hint "Commit or ref"
        ref=${!shift_by}
        ;;
    -a|--annotated)# _FLAG
        # Create an annotated tag (git tag -a)
        is_annotated=true
        ;;
    -f|--force)# _FLAG
        # Force overwrite if tag already exists
        is_force=true
        ;;
    --dry-run|--what-if)# _FLAG
        # Show what would be tagged without doing it
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
Create a git tag (git tag).

Lightweight tags are created by default. Use --annotated or --message to
create an annotated tag with metadata.

Emits a JSONL record with the tag name, commit, and type.

Output record fields: name, commit, type (lightweight/annotated)
" \
        --example "Lightweight tag" "--name v1.0.1" \
        --example "Annotated tag" "--name v1.1.0 --message 'Release v1.1.0'" \
        --example "Tag a specific commit" "--name hotfix --ref abc1234" \
        --example "Force overwrite" "--name v1.0.0 --force"
    return 0
fi

if [[ -z "$name" ]]; then
    error_msg="--name is required (e.g. bu new-git-tag --name v1.0.0)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local commit
commit=$(git rev-parse --short "$ref" 2>/dev/null) || {
    error_msg="Invalid ref: $ref"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

if "$is_dry_run"; then
    local type="lightweight"
    "$is_annotated" || [[ -n "$message" ]] && type="annotated"
    bu_out_record name="$name" commit="$commit" type="$type" status="dry-run" | bu_out --format jsonl
    bu_scope_pop_function
    return 0
fi

local type="lightweight"
local -a cmd=(git tag)
if "$is_annotated" || [[ -n "$message" ]]; then
    type="annotated"
    cmd+=(--annotate)
    [[ -n "$message" ]] && cmd+=(-m "$message")
fi
"$is_force" && cmd+=(-f)
cmd+=("$name" "$ref")
if ((${#remaining_options[@]} > 0)); then cmd+=("${remaining_options[@]}"); fi

"${cmd[@]}" 2>/dev/null || {
    error_msg="Failed to create tag: $name (already exists? use --force)"
    bu_autohelp
    bu_scope_pop_function
    return 1
}

bu_out_record name="$name" commit="$commit" type="$type" | bu_out --format jsonl

bu_scope_pop_function
}

__bu_bu_new_git_tag_main "$@"
