#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Tab-Execute: true
# Synopsis: Show BashTab's own release version
# Fields: version tag sha dirty module dir
function __bu_bu_get_version_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local columns=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        bu_validate_positional "${!shift_by}"
        format=${!shift_by}
        ;;
    --columns)# COLUMNS
        # Fields to display, in order (comma-separated)
        bu_parse_positional $# --enum version tag sha dirty module dir enum-- --hint "Comma-separated fields"
        columns=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        bu_parse_error_enum "$1"
        break
        ;;
    esac
    if "$is_help"
    then
        break
    fi
    if (( $# < shift_by ))
    then
        bu_parse_error_argn "$1" $#
        break
    fi
    shift "$shift_by"
done
local remaining_options=("$@")
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Show BashTab's own release identity.

version  — git describe (e.g. v2026.08.15-3-g1f4ae9c, or -dirty when the
           working tree has uncommitted changes). Datetime tags are cut by
           release.sh; see docs/releasing.md.
tag      — nearest release tag (vYYYY.MM.DD[.N])
sha      — full commit hash of the checkout
dirty    — whether the working tree has uncommitted changes
module   — BU_TOP_LEVEL_MODULE (the active top-level module)
dir      — checkout directory

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table. Use --format to override.
" \
        --example "Show version" "" \
        --example "Show version as JSON" "--format json" \
        --example "Show only the tag" "--columns tag"
    return 0
fi

# These are computed once at activation (see bu_entrypoint.sh); re-activate
# after pulling a new release to refresh them.
local version=${BU_VERSION:-unknown}
local tag=${BU_VERSION_TAG:-unknown}
local sha=${BU_REPO_SHA1:-unknown}
local dirty=false
[[ "$version" == *-dirty ]] && dirty=true
local module=${BU_TOP_LEVEL_MODULE:-}
local dir=${BU_REPO_DIR:-$PWD}

printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$version" "$tag" "$sha" "$dirty" "$module" "$dir" \
    | bu_out_from_tsv --columns version,tag,sha,dirty,module,dir \
    | bu_out --format "$format" ${columns:+--columns "$columns"}

bu_scope_pop_function
}

__bu_bu_get_version_main "$@"
