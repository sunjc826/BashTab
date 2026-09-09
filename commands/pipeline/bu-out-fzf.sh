#!/usr/bin/env bash
# Pipeline: passthrough
# Dispatch: source
# Synopsis: Display a JSONL stream in an interactive fzf selector
function __bu_bu_out_fzf_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v fzf &>/dev/null || { echo "fzf is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_multi=false
local query=
local format=auto
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -m|--multi)# _FLAG
        # Allow selecting multiple records (TAB to toggle, ENTER to accept)
        is_multi=true
        ;;
    -q|--query)# QUERY
        # Initial fzf query string
        bu_parse_positional $# --hint "Initial filter query"
        query=${!shift_by}
        ;;
    --format)# FORMAT
        # Output format
        bu_parse_positional $# --enum ${BU_OUT_FORMATS[@]} enum-- --hint "Output format"
        format=${!shift_by}
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
if bu_env_is_in_autocomplete
then
    bu_autocomplete
    return 0
fi

if "$is_help"
then
    bu_autohelp \
        --description "
Interactively select records from the JSONL stream with fzf (the Out-GridView of bash).
Selected records continue downstream as JSONL; cancelling (ESC) produces
an empty stream. The preview pane shows the record pretty-printed.
Requires a full pass over the stream before the picker opens.
" \
        --example "Pick a command" "" \
        --example "Pick several" "--multi" \
        --example "Start pre-filtered" "--query get-"
    return 0
fi

if [[ ! -t 0 && ! -t 1 ]]
then
    bu_log_warn "bu out-fzf: neither stdin nor stdout is a TTY; the picker may not render"
fi

# Buffer the stream so fzf can read records on stdin (its UI uses /dev/tty)
local buffer
buffer=$(mktemp)
bu_scope_add_cleanup rm -f "$buffer"
cat > "$buffer"

local -a fzf_args=(--preview 'jq -C . 2>/dev/null || cat' --preview-window 'up,40%,border-bottom')
"$is_multi" && fzf_args+=(--multi)
[[ -n "$query" ]] && fzf_args+=(--query "$query")

fzf "${fzf_args[@]}" < "$buffer" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_out_fzf_main "$@"
