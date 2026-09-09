#!/usr/bin/env bash
# Pipeline: producer
# Fields: path action dry_run
# Dispatch: source
# Synopsis: Push the current directory onto the pushd stack
# Help-Topic: locations
function __bu_bu_push_location_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local path=
local format=auto
local is_help=false
local is_dry_run=false
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
        format=${!shift_by}
        ;;
    --dry-run|--what-if) # _FLAG
        is_dry_run=true
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # Positional: registry dir names plus directories
            autocompletion=(--ret __bu_push_location_complete ret--)
        fi
        if [[ -z "$path" ]]
        then
            path=$1
        else
            bu_parse_error_enum "$1"
        fi
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Push the current directory onto the stack and cd elsewhere (PowerShell Push-Location, pushd).
Runs in the current shell, so the cd takes effect. Without a path, swaps
the top two stack entries. Emits the new location as a record; pair with
bu pop-location and inspect with bu get-location-stack.
" \
        --example "Go somewhere, remembering here" "/tmp" \
        --example "Swap with the previous directory" ""
    return 0
fi

if [[ -n "$path" && ! -d "$path" ]] \
    && [[ -n "${BU_LOCATION_ALIASES[$path]:-}" || -n "${BU_LOCATION_REGISTRY[$path]:-}" ]]
then
    # Not an existing directory, but a registered dir name (alias-aware).
    # A real ./name directory always beats a registered name (checked above).
    if bu_location_resolve "$path" --kind dir
    then
        path=${BU_RET[0]}
    fi
fi

if "$is_dry_run"; then
    if [[ -n "$path" ]]; then
        bu_out_record path="$path" action="would-push" dry_run:=true | bu_out --format "$format"
    else
        bu_out_record action="would-swap-top-two" dry_run:=true | bu_out --format "$format"
    fi
else
# Runs sourced, so pushd affects the current shell's directory stack
local rc=0
if [[ -n "$path" ]]
then
    pushd -- "$path" &>/dev/null || rc=1
else
    pushd &>/dev/null || rc=1
fi

if ((rc != 0))
then
    error_msg="pushd failed${path:+": $path"}"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_out_record path="$PWD" | bu_out --format "$format"

fi
bu_scope_pop_function
}

# Completion helper: registry dir names (with aliases) plus current-directory
# subdirectories.
__bu_push_location_complete()
{
    BU_RET=()
    local name
    while IFS= read -r name
    do
        [[ -n "$name" ]] && BU_RET+=("$name")
    done < <(bu_location_names --kind dir --with-aliases 2>/dev/null)
    local d
    for d in ./*/
    do
        [[ -d "$d" ]] || continue
        d=${d%/}
        d=${d#./}
        BU_RET+=("$d")
    done
}

__bu_bu_push_location_main "$@"
