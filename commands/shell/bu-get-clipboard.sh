#!/usr/bin/env bash
# Pipeline: producer
# Fields: text
# Dispatch: source
# Synopsis: Read the system clipboard contents
function __bu_bu_get_clipboard_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v pbpaste &>/dev/null && exit 0
    command -v wl-paste &>/dev/null && exit 0
    command -v xclip &>/dev/null && exit 0
    command -v xsel &>/dev/null && exit 0
    echo "a clipboard tool is required (pbpaste, wl-paste, xclip, or xsel)" >&2
    exit 1
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local format=auto
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
Read the system clipboard as a record (PowerShell Get-Clipboard).
Emits one record with a text field containing the full clipboard contents.
Uses the first available backend: pbpaste (macOS), wl-paste (Wayland),
xclip, xsel (X11). To extract lines instead, pipe .text through
'jq -r .text'.
" \
        --example "Read clipboard" ""
    return 0
fi

local text
if command -v pbpaste &>/dev/null
then
    text=$(pbpaste)
elif command -v wl-paste &>/dev/null
then
    text=$(wl-paste -n 2>/dev/null)
elif command -v xclip &>/dev/null
then
    text=$(xclip -selection clipboard -o 2>/dev/null)
elif command -v xsel &>/dev/null
then
    text=$(xsel --clipboard --output 2>/dev/null)
else
    error_msg="No clipboard tool found (pbpaste, wl-paste, xclip, or xsel)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

bu_out_record text="$text" | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_clipboard_main "$@"
