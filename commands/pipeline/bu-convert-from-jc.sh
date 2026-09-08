#!/usr/bin/env bash
# Pipeline: recordify_jc
# Dispatch: source
# Synopsis: Convert structured command output to JSONL via jc parsers
function __bu_bu_convert_from_jc_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local parser=
local is_discover=false
local is_help=false
local format=auto
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
    --parser)# PARSER
        # jc parser name for pipe mode (e.g. ls, ps, df)
        bu_parse_positional $# --enum ls ps df dig free mount uptime uname env id du stat ifconfig netstat arp dpkg-l iostat vmstat lsof wc rpm-qi pacman systemctl systemctl-luf iptables pip-list enum-- --hint "jc parser name"
        parser=${!shift_by}
        ;;
    --discover)# _FLAG
        # Output the record fields this parser emits (for pipeline completion).
        # Runs the parser on a sample invocation and extracts keys from the
        # first record. Does not read stdin.
        is_discover=true
        ;;
    *)
        # Magic mode: positional args are the command to run through jc.
        # jc auto-detects the parser from the command name.
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
Convert the output of a Unix command to JSONL via jc (JSON Convert).
Pipe mode:  <command> | bu convert-from-jc --parser NAME
Magic mode: bu convert-from-jc <command> [args...]
    jc auto-detects the parser from the command name.

Requires jc (pip install jc). See https://github.com/kellyjonbrazil/jc
" \
        --example "Pipe mode (ls)" "--parser ls" \
        --example "Magic mode (ps)" "ps aux" \
        --example "Filter with BashTab" "--parser df | bu where '.use_percent > 50'"
    return 0
fi

if ! command -v jc &>/dev/null
then
    error_msg="jc is required. Install it with: pip install jc"
    bu_autohelp
    bu_scope_pop_function
    return 1
fi

# Determine the jc invocation
if [[ -n "$parser" ]]
then
    # Pipe mode: read stdin, convert with the specified parser
    if "$is_discover"
    then
        # --discover: run jc on a sample invocation to get the field schema.
        # For pipe-mode parsers, we run the underlying command ourselves.
        # The sample commands are the same ones used to seed the static field map.
        __bu_convert_from_jc_discover "$parser"
        bu_scope_pop_function
        return $?
    fi
    jc --$parser | jq -c '.[]' 2>/dev/null | bu_out --format "$format"
else
    # Magic mode: pass-through to jc with all remaining args.
    # jc auto-detects the parser from the command name.
    if "$is_discover"
    then
        # For magic mode discovery, we can't easily know the parser ahead of
        # time. Output null fields (passthrough) — probing can handle it.
        __bu_out_assert_jq 2>/dev/null && "$BU_OUT_JQ" -cn '{outputFields: null}'
        bu_scope_pop_function
        return 0
    fi
    jc "$@" | jq -c '.[]' 2>/dev/null | bu_out --format "$format"
fi

bu_scope_pop_function
}

# ```
# *Description*:
# Run a sample invocation of a jc parser and emit the field names of the
# first record as a JSON query plan (same format as bu query-object --debug).
# Used by the pipeline completion system for static field analysis.
#
# *Params*:
# - `$1`: Parser name (e.g. ls, ps, df)
# ```
__bu_convert_from_jc_discover()
{
    local -r parser=$1

    # Map parser to a sample command that produces typical output
    local sample_cmd=
    case "$parser" in
        ls)       sample_cmd="ls -la /tmp" ;;
        ps)       sample_cmd="ps aux" ;;
        df)       sample_cmd="df" ;;
        dig)      sample_cmd="dig example.com" ;;
        free)     sample_cmd="free" ;;
        mount)    sample_cmd="mount" ;;
        uptime)   sample_cmd="uptime" ;;
        uname)    sample_cmd="uname -a" ;;
        env)      sample_cmd="env" ;;
        id)       sample_cmd="id" ;;
        du)       sample_cmd="du /tmp" ;;
        stat)     sample_cmd="stat /etc/hosts" ;;
        ifconfig) sample_cmd="ifconfig" ;;
        netstat)  sample_cmd="netstat -tlnp" ;;
        arp)      sample_cmd="arp -a" ;;
        dpkg-l)   sample_cmd="dpkg -l" ;;
        iostat)   sample_cmd="iostat" ;;
        vmstat)   sample_cmd="vmstat" ;;
        lsof)     sample_cmd="lsof -c bash 2>/dev/null | head -20" ;;
        wc)       sample_cmd="wc /etc/hosts" ;;
        rpm-qi)   sample_cmd="rpm -qi bash 2>/dev/null || rpm -qia 2>/dev/null | head -80" ;;
        pacman)   sample_cmd="pacman -Qi bash 2>/dev/null || pacman -Qi 2>/dev/null | head -80" ;;
        systemctl) sample_cmd="systemctl list-units --all 2>/dev/null | head -60" ;;
        systemctl-luf) sample_cmd="systemctl list-unit-files 2>/dev/null | head -40" ;;
        iptables) sample_cmd="iptables -L -v -n 2>/dev/null | head -40" ;;
        pip-list) sample_cmd="pip list --format=columns 2>/dev/null" ;;
    esac

    if [[ -z "$sample_cmd" ]]
    then
        # Unknown parser: can't statically determine fields
        __bu_out_assert_jq 2>/dev/null && "$BU_OUT_JQ" -cn '{outputFields: null}'
        return 0
    fi

    local first_record
    first_record=$(eval "$sample_cmd" 2>/dev/null | jc --$parser 2>/dev/null | jq -c '.[0]' 2>/dev/null)
    if [[ -z "$first_record" || "$first_record" == null ]]
    then
        __bu_out_assert_jq 2>/dev/null && "$BU_OUT_JQ" -cn '{outputFields: null}'
        return 0
    fi

    local keys_json
    keys_json=$(jq -r 'keys_unsorted[]' <<<"$first_record" 2>/dev/null)
    local -a fields=()
    mapfile -t fields <<<"$keys_json"

    if ((${#fields[@]} == 0))
    then
        __bu_out_assert_jq 2>/dev/null && "$BU_OUT_JQ" -cn '{outputFields: null}'
        return 0
    fi

    local fields_json
    fields_json=$(jq -cn --args '$ARGS.positional' -- "${fields[@]}")
    jq -cn --argjson fields "$fields_json" '{outputFields: $fields}'
}

__bu_bu_convert_from_jc_main "$@"
