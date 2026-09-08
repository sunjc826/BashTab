#!/usr/bin/env bash
# Pipeline: codec
# Dispatch: source
# Synopsis: Encode JSONL records or text to base64
function __bu_bu_convert_to_base64_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v base64 &>/dev/null || { echo "base64 is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local wrap=false
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -w|--wrap)# _FLAG
        # Keep base64's default line wrapping (76 columns) instead of a single line
        wrap=true
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
Encode stdin as base64 on stdout ([Convert]::ToBase64String analog).
Emits a single unwrapped line by default (like PowerShell); --wrap keeps
the traditional 76-column wrapping. Works portably (no GNU-only flags).
" \
        --example "Encode a string" "" \
        --example "Decode back" ""
    return 0
fi

if "$wrap"
then
    base64
else
    # Portable single-line output (GNU base64 -w0 is not available on macOS)
    base64 | tr -d '\n'
    echo
fi

bu_scope_pop_function
}

__bu_bu_convert_to_base64_main "$@"
