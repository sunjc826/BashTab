#!/usr/bin/env bash
# Pipeline: standalone
# Dispatch: source
# Synopsis: Open an interactive bash on a remote host with the project loaded
function __bu_bu_enter_remote_session_main()
{
local -r invocation_dir=$PWD

# shellcheck source=./__bu_entrypoint_decl.sh
source "$BU_NULL"

bu_scope_push_function
bu_run_log_command "$@"

local spec=
local remote_dir=
local -a bootstrap_opts=()
local is_help=false
local error_msg=
local autocompletion=()
local shift_by=
while (($#))
do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --remote-dir)# REMOTE_DIR
        # Directory to activate the project in on the remote host
        bu_parse_positional $# --hint "Remote directory for project activation"
        remote_dir=${!shift_by}
        ;;
    --bootstrap-opt)# BOOTSTRAP_OPT
        # Extra option passed verbatim to the bootstrap callback; repeatable
        bu_parse_positional $# --hint "Bootstrap callback option"
        bootstrap_opts+=("${!shift_by}")
        ;;
    -h|--help)# _FLAG
        # Print help
        is_help=true
        ;;
    -*)
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
    *)
        spec=$1
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
Open an interactive bash on a remote host with the project environment
loaded.  The shell's rc is assembled from three parts in order: the user's
own rc files (/etc/profile and ~/.bashrc, unsilenced), the bootstrap-callback
payload (BU_REMOTE_BOOTSTRAP_CALLBACK with BU_REMOTE_BOOTSTRAP_OPTS, or the
default bootstrap), and an interactive tail that sets BU_REMOTE_SESSION,
BU_REMOTE_SESSION_ORIGIN, and a [spec] prompt prefix.  The local machine
(localhost/\$HOSTNAME as \$USER) is short-circuited to a direct bash
invocation (zero network).

Embedders may register BU_REMOTE_CONTEXT_PARSER as the name of a
bu_parse_inject-contract function; its -*/--* flags Tab-complete natively
alongside the built-ins.  Nested sessions are refused.
" \
        --example "Enter a session on web01" "web01" \
        --example "Enter with a context" "web01 --context prod"
    return 0
fi

if [[ -n "${BU_REMOTE_SESSION:-}" ]]
then
    bu_log_err "Already inside a remote session[$BU_REMOTE_SESSION]; nesting is refused"
    bu_scope_pop_function
    return 1
fi

if [[ -z "$spec" ]]
then
    bu_log_err "A remote spec is required (e.g. bu enter-remote-session web01)"
    bu_scope_pop_function
    return 1
fi

local normalized user host
if ! bu_remote_spec_normalize "$spec"
then
    bu_scope_pop_function
    return 1
fi
normalized=$BU_RET
user=${BU_RET_MAP[user]}
host=${BU_RET_MAP[host]}

# Local origin (user@hostname) for BU_REMOTE_SESSION_ORIGIN.
__bu_remote_local_user
local local_user=$BU_RET
local local_host=${HOSTNAME:-}
[[ -z "$local_host" ]] && local_host=$(hostname 2>/dev/null)
local origin="$local_user@$local_host"

# Bridge --bootstrap-opt / context-parser opts into the array the bootstrap
# callback reads.
local -a BU_REMOTE_BOOTSTRAP_OPTS=("${bootstrap_opts[@]}")

# Assemble the interactive rc: user rc files, bootstrap payload, interactive tail.
local rc_content
printf -v rc_content '%s\n' \
    '[[ -f /etc/profile ]] && . /etc/profile' \
    '[[ -f ~/.bashrc ]] && . ~/.bashrc'

if [[ -n "${BU_REMOTE_BOOTSTRAP_CALLBACK:-}" ]]
then
    rc_content+=$("$BU_REMOTE_BOOTSTRAP_CALLBACK" "$remote_dir" ${BU_REMOTE_BOOTSTRAP_OPTS[@]+"${BU_REMOTE_BOOTSTRAP_OPTS[@]}"})
else
    rc_content+=$(__bu_remote_default_bootstrap)
fi
rc_content+=$'\n'

local ps1_prefix
printf -v ps1_prefix '\\[\\e[1;35m\\][%s]\\[\\e[0m\\] ' "$normalized"
local ps1_line="export PS1='${ps1_prefix}'\"\$PS1\""

rc_content+=$'set +e\nexport BU_REMOTE_SESSION='"${normalized}"$'\nexport BU_REMOTE_SESSION_ORIGIN='"${origin}"$'\n'"${ps1_line}"$'\n'

local rc=0
if [[ "$user" == "$local_user" ]] && __bu_remote_is_local_host "$host"
then
    # Local short-circuit: same rc assembly, direct bash, zero network.
    local rc_file
    rc_file=$(mktemp "$BU_TMP_DIR/bu_remote_session_rc.XXXXXXXXXX")
    bu_scope_add_cleanup rm -f "$rc_file"
    printf '%s' "$rc_content" > "$rc_file"
    bash --rcfile "$rc_file" -i
    rc=$?
else
    # One ssh connection ships the rc inside the remote command, which writes
    # it to a remote mktemp file, appends a self-delete line, then execs bash.
    local rc_q
    printf -v rc_q '%q' "$rc_content"
    local remote_cmd
    printf -v remote_cmd 'f=$(mktemp) && printf %%s %s > "$f" && printf "\\nrm -f -- %%s\\n" "$f" >> "$f" && exec bash --rcfile "$f" -i' "$rc_q"
    local -a opts=()
    bu_remote_ssh_opts "$normalized" opts || { bu_log_err "Failed to build ssh options for $normalized"; bu_scope_pop_function; return 1; }
    ssh -t "${opts[@]}" "$normalized" "$remote_cmd"
    rc=$?
fi

bu_scope_pop_function
return "$rc"
}

__bu_bu_enter_remote_session_main "$@"
