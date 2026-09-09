#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Run a command or script on remote hosts over ssh
function __bu_bu_invoke_remote_command_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local -a hosts=()
local remote_dir=
local host_field=
local -a bootstrap_opts=()
local no_host_field=false
local format=jsonl
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
local -a cmd=()
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --host)# HOST
        # Remote host spec ([user@]host); repeatable
        bu_parse_positional $# --hint "Remote host spec ([user@]host)"
        hosts+=("${!shift_by}")
        ;;
    --host-field)# HOST_FIELD
        # Read host specs from piped JSONL records (extract this field)
        bu_parse_positional $# --hint "JSONL record field holding the host spec"
        host_field=${!shift_by}
        ;;
    --remote-dir)# REMOTE_DIR
        # Directory to activate the project in on the remote host
        bu_parse_positional $# --hint "Remote directory for project activation"
        remote_dir=${!shift_by}
        ;;
    --no-host-field)# _FLAG
        # Do not inject a host field into JSONL records
        no_host_field=true
        ;;
    --bootstrap-opt)# BOOTSTRAP_OPT
        # Extra option passed verbatim to the bootstrap callback; repeatable
        bu_parse_positional $# --hint "Bootstrap callback option"
        bootstrap_opts+=("${!shift_by}")
        ;;
    --format)# FORMAT
        # Output format (jsonl is passthrough; others go through the output layer)
        bu_parse_positional $# --enum "${BU_OUT_FORMATS[@]}" enum-- --hint "Output format (jsonl is passthrough)"
        format=${!shift_by}
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    --)
        shift
        cmd=("$@")
        set --
        break
        ;;
    *)
        if [[ -n "${BU_REMOTE_CONTEXT_PARSER:-}" ]] && declare -F "$BU_REMOTE_CONTEXT_PARSER" >/dev/null 2>&1
        then
            if ! bu_parse_inject "$BU_REMOTE_CONTEXT_PARSER" "$@"
            then
                bu_parse_error_enum "$1"
                break
            fi
        else
            bu_parse_error_enum "$1"
            break
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
Run a command (after --) or a script (piped on stdin) on one or more remote
hosts over ssh, reusing a live ControlMaster session when one exists.  JSONL
records produced remotely get a \"host\" field injected (disable with
--no-host-field); non-JSON lines pass through verbatim.  The local machine
(localhost/\$HOSTNAME as \$USER) is short-circuited through a clean
env -i bash -s, so marshal->run->tag->rc works with zero network.

Provide a command after --, or pipe a script on stdin (script mode).  One of
the two is required.  Hosts may also come from piped JSONL records via
--host-field FIELD: each record's FIELD is extracted, deduped order-preserving,
and appended after any explicit --host flags.  With --host-field, stdin
carries the records, so a command after -- is required and script mode is
unavailable.  Extra options for the bootstrap callback are forwarded
verbatim with repeatable --bootstrap-opt OPT.

Embedders may register BU_REMOTE_CONTEXT_PARSER as the name of a
bu_parse_inject-contract function; it runs in this command's dynamic scope
and may append to bootstrap_opts or assign remote_dir directly, returning 1
for tokens it does not own.  Its flags Tab-complete natively alongside the
built-ins with no extra completion code.
" \
        --example "Run get-module on two hosts" "--host web01 --host web02 -- get-module" \
        --example "Pipe a script block" "echo 'get-module' | bu invoke-remote-command --host web01" \
        --example "Fan out to an inventory" "bu get-server --where env=prod | bu invoke-remote-command --host-field host -- get-module"
    return 0
fi

if [[ -n "$host_field" ]]
then
    if [[ -t 0 ]]
    then
        bu_log_err "--host-field requires piped JSONL records on stdin (a terminal has no records)"
        bu_scope_pop_function
        return 1
    fi
    if ((${#cmd[@]} == 0))
    then
        bu_log_err "--host-field reads host records from stdin, so script mode unavailable; provide a command after --"
        bu_scope_pop_function
        return 1
    fi
    __bu_out_assert_jq || { bu_scope_pop_function; return 1; }

    local _hf_host _hf_existing _hf_seen
    while IFS= read -r _hf_host
    do
        [[ -n "$_hf_host" ]] || continue
        _hf_seen=false
        for _hf_existing in "${hosts[@]}"
        do
            if [[ "$_hf_existing" == "$_hf_host" ]]
            then
                _hf_seen=true
                break
            fi
        done
        "$_hf_seen" || hosts+=("$_hf_host")
    done < <("$BU_OUT_JQ" -Rr --arg f "$host_field" 'try (fromjson | .[$f] | select(type == "string" and . != "")) catch empty')
fi

if ((${#hosts[@]} == 0))
then
    bu_log_err "At least one --host is required"
    bu_scope_pop_function
    return 1
fi

local -a mode_args=()
if ((${#cmd[@]}))
then
    mode_args=(command "${cmd[@]}")
elif [[ ! -t 0 ]]
then
    local script_block
    script_block=$(cat)
    mode_args=(script "$script_block")
else
    bu_log_err "No command after -- and stdin is a terminal; provide a command or pipe a script"
    bu_scope_pop_function
    return 1
fi

# Marshal the payload to a temp file under the framework tmp dir
local tmp_file
tmp_file=$(mktemp "$BU_TMP_DIR/bu_remote_invoke.XXXXXXXXXX")
bu_scope_add_cleanup rm -f "$tmp_file"

local -a BU_REMOTE_BOOTSTRAP_OPTS=("${bootstrap_opts[@]}")
bu_remote_build_script "$remote_dir" "${mode_args[@]}" > "$tmp_file"

local inject=true
"$no_host_field" && inject=false

local rc=0
if [[ "$format" == jsonl || "$format" == auto ]]
then
    bu_remote_invoke "$tmp_file" "$inject" "${hosts[@]}"
    rc=$?
else
    bu_remote_invoke "$tmp_file" "$inject" "${hosts[@]}" | bu_out --format "$format"
    rc=${PIPESTATUS[0]}
fi

bu_scope_pop_function
return "$rc"
}

__bu_bu_invoke_remote_command_main "$@"
