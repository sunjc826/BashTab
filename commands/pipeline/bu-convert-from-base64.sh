#!/usr/bin/env bash
# Pipeline: codec
# Dispatch: source
# Synopsis: Decode base64-encoded data to JSONL
function __bu_bu_convert_from_base64_main()
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

local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
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
Decode base64 from stdin to stdout ([Convert]::FromBase64String analog).
Accepts both wrapped and single-line input (GNU base64 -d and BSD
base64 -D both ignore newlines). See bu convert-to-base64 to encode.
" \
        --example "Decode a token" ""
    return 0
fi

# -d is GNU, -D is BSD/macOS; try -d first, fall back to -D
if base64 -d </dev/null &>/dev/null
then
    base64 -d
else
    base64 -D
fi

bu_scope_pop_function
}

__bu_bu_convert_from_base64_main "$@"
