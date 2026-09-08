#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Tab-Execute: true
# Synopsis: List loaded BashTab modules
# Help-Topic: modules
# Fields: name rank version path describe branch dirty
function __bu_bu_get_module_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
local columns=
local no_status=false
local is_help=false
local error_msg=
local options_finished=false
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
        bu_parse_positional $# --enum name rank version path describe branch dirty enum-- --hint "Comma-separated fields"
        columns=${!shift_by}
        ;;
    --no-status)# _FLAG
        # Skip live git probes (describe/branch/dirty)
        no_status=true
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
List all modules registered in BU_MODULE_LIST.
Each entry has the form \"name:version:preinit_path;\".
Module scripts set this when sourced;
top-level projects set it in their activate script.

The version field is declarative: a hardcoded string the module script
registers and nobody bumps. describe, branch, and dirty are live git
identity, probed from the directory containing each module's registered
preinit path — a module outside a git repo (or --no-status) reports empty
describe/branch and dirty=null.

Output is structured: piped output defaults to JSONL, terminal output
defaults to a table. Use --format to override.
" \
        --example "List modules" "" \
        --example "List modules as a JSON array" "--format json" \
        --example "List modules as a list" "--format list" \
        --example "Modules with uncommitted changes" "| bu query-object where dirty -eq true" \
        --example "Skip live git probes" "--no-status"
    return 0
fi

# Parse BU_MODULE_LIST: "name:version:path;name:version:path;..."
local -a entries=()
if [[ -n "$BU_MODULE_LIST" ]]; then
    local _ifs=$IFS
    IFS=';'
    entries=($BU_MODULE_LIST)
    IFS=$_ifs
fi

if ((${#entries[@]} == 0))
then
    # Hints go to stderr so they never pollute the structured stream
    bu_log_info "No modules registered."
    bu_log_info "Modules register by appending to BU_MODULE_LIST in their module script."
    bu_log_info "Use 'bu new-module --name <name>' to scaffold a properly registered module."
else
    # Stream one typed record per entry, then let bu_out decide presentation
    # (table on a terminal, JSONL when piped).  bu_out_record forks one jq per
    # record — fine here because module registries are small.
    local entry
    {
        for entry in "${entries[@]}"
        do
            [[ -z "$entry" ]] && continue
            local name=${entry%%:*}
            local rest=${entry#*:}
            local version=${rest%%:*}
            local path=${rest#*:}

            # Precedence rank (lower wins bare-name collisions). Read from
            # BU_MODULE_RANK; null when the module-list parser never ranked
            # this entry (e.g. a hand-set BU_MODULE_LIST in tests/subshells).
            local rank=null
            if [[ -n "${BU_MODULE_RANK[$name]:-}" ]]; then
                rank=${BU_MODULE_RANK[$name]}
            fi

            local describe=
            local branch=
            local dirty=null

            if ! "$no_status"
            then
                # Probe only absolute paths whose directory exists.  A bogus
                # or relative registered path must not fall through to
                # probing the caller's CWD.
                local dir=
                if [[ "$path" == /* ]]
                then
                    bu_dirname "$path"
                    dir=$BU_RET
                fi
                if [[ -n "$dir" && -d "$dir" ]]
                then
                    describe=$(git -C "$dir" describe --tags --always --dirty 2>/dev/null || true)
                    branch=$(git -C "$dir" branch --show-current 2>/dev/null || true)
                    if [[ -n "$describe" ]]
                    then
                        if [[ "$describe" == *-dirty ]]
                        then
                            dirty=true
                        else
                            dirty=false
                        fi
                    fi
                fi
            fi

            bu_out_record name="$name" rank:="$rank" version="$version" path="$path" \
                describe="$describe" branch="$branch" dirty:="$dirty"
        done
    } | bu_out --format "$format" ${columns:+--columns "$columns"}
fi

bu_scope_pop_function
}

__bu_bu_get_module_main "$@"
