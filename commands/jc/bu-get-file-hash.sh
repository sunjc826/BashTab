#!/usr/bin/env bash
# Pipeline: producer
# Dispatch: source
# Synopsis: Compute the cryptographic hash of a file
function __bu_bu_get_file_hash_main()
{
# --is-compatible: magic flag checked by the framework at registration time.
# Exit 0 if this command can run on the current system, non-zero otherwise.
# stderr becomes the reason shown in `bu` help.
if [[ "$1" == "--is-compatible" ]]; then
    command -v jc &>/dev/null || { echo "jc is required" >&2; exit 1; }
    command -v sha256sum &>/dev/null || command -v md5sum &>/dev/null || { echo "a *sum utility (coreutils) is required" >&2; exit 1; }
    exit 0
fi
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local is_help=false
local format=auto
local algorithm=sha256
local -a files=()
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
    -a|--algorithm)# ALGORITHM
        # Hash algorithm to use
        bu_parse_positional $# --enum md5 sha1 sha256 sha512 enum-- --hint "Hash algorithm"
        algorithm=${!shift_by}
        ;;
    -h|--help)# _FLAG
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
        --description "Compute file hashes (PowerShell Get-FileHash). Wraps the coreutils *sum tools and parses output with jc." \
        --example "SHA-256 of one file" "./app.tar.gz" \
        --example "MD5 of several files" "--algorithm md5 a.bin b.bin"
    return 0
fi

if ((${#files[@]} == 0))
then
    error_msg="Missing required file path (e.g. bu get-file-hash ./app.tar.gz)"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

local sum_cmd=
case "$algorithm" in
md5)    sum_cmd=md5sum ;;
sha1)   sum_cmd=sha1sum ;;
sha256) sum_cmd=sha256sum ;;
sha512) sum_cmd=sha512sum ;;
esac

if ! command -v "$sum_cmd" &>/dev/null
then
    error_msg="$sum_cmd is required for --algorithm $algorithm"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

"$sum_cmd" -- "${files[@]}" 2>/dev/null | jc --hashsum 2>/dev/null | jq -c 'if type == "array" then .[] else . end' 2>/dev/null | bu_out --format "$format"

bu_scope_pop_function
}

__bu_bu_get_file_hash_main "$@"
