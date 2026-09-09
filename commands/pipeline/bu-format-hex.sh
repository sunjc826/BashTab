#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Format binary data as a hex dump
function __bu_bu_format_hex_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v xxd &>/dev/null && exit 0
    command -v hexdump &>/dev/null && exit 0
    command -v od &>/dev/null && exit 0
    echo "a hex dump tool is required (xxd, hexdump, or od)" >&2
    exit 1
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a files=()
local length=
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    -n|--length)# N
        # Only dump the first N bytes
        bu_parse_positional $# --hint "Byte count"
        length=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    *)
        if bu_env_is_in_autocomplete
        then
            # File positional: complete files
            autocompletion=("${BU_AUTOCOMPLETE_SPEC_FILE[@]}")
        fi
        files+=("$1")
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
Hex-dump binary data (PowerShell Format-Hex, friendly xxd).
Reads files or stdin and writes a hex+ASCII dump to the terminal (this is
a text sink, not a record stream). Prefers xxd, falls back to hexdump -C,
then od. Extra backends' flags can be passed after --.
" \
        --example "Dump a file" "app.bin" \
        --example "First 64 bytes" "app.bin --length 64" \
        --example "Dump a stream" ""
    return 0
fi

# Pick a backend
local -a dump_cmd=()
if command -v xxd &>/dev/null
then
    dump_cmd=(xxd -g1)
    [[ -n "$length" ]] && dump_cmd+=(-l "$length")
elif command -v hexdump &>/dev/null
then
    dump_cmd=(hexdump -C)
    [[ -n "$length" ]] && dump_cmd+=(-n "$length")
else
    dump_cmd=(od -A x -t x1z -v)
    [[ -n "$length" ]] && dump_cmd+=(-N "$length")
fi

if ((${#files[@]} > 0))
then
    "${dump_cmd[@]}" -- "${files[@]}"
else
    "${dump_cmd[@]}"
fi

bu_scope_pop_function
}

__bu_bu_format_hex_main "$@"
