# bash-ide source=./bu_core_base.sh
# bash-ide source=./bu_core_out.sh
# bash-ide source=./bu_core_preinit.sh

# Remote command execution over ssh, with a local short-circuit for this
# machine.  The whole design keeps two structural properties so the code is
# testable with zero network:
#
#   (a) ssh is invoked by PATH resolution, never by absolute path, so a stub
#       ssh script prepended to PATH can record argv and play back canned
#       responses.
#   (b) The local short-circuit runs the SAME marshaled payload through
#       `env -i ... bash -s` instead of ssh, so script assembly, bootstrap
#       embedding, stdout tagging, stderr prefixing, and rc propagation are
#       exercised end-to-end without any network.
#
# Specs are `[user@]host`; they are normalized to `user@host` with each part
# restricted to [A-Za-z0-9._-] so that ControlMaster socket filenames are
# BIJECTIVE with (normalized) specs.

# jq program that tags each JSONL line with the originating host.  Kept in a
# named constant so tests exercise exactly what ships.
if [[ -z "${BU_REMOTE_JQ_HOST_FILTER:-}" ]]
then
    declare -g -r BU_REMOTE_JQ_HOST_FILTER='. as $l | try ($l | fromjson | .host = $host | tojson) catch $l'
fi

# Resolve the local username ($USER, falling back to `id -un` in stripped
# environments where USER is unset).
#
# @set BU_RET local username
# bash-ide parse-func-sig
__bu_remote_local_user()
{
    BU_RET=${USER:-}
    if [[ -z "$BU_RET" ]]
    then
        BU_RET=$(id -un 2>/dev/null)
    fi
}

# Normalize a remote spec `[user@]host` into `user@host`.  A bare host gets
# the local $USER.  Each part is validated against [A-Za-z0-9._-] so socket
# filenames stay bijective with specs.
#
# @arg $1 {string} spec spec, e.g. `web01` or `deploy@web01`
# @set BU_RET normalized `user@host`
# @set BU_RET_MAP[user] user part
# @set BU_RET_MAP[host] host part
#
# @returns
# - Exit code 0 on success, 1 on an invalid spec
# bash-ide parse-func-sig
bu_remote_spec_normalize()
{
    local -r spec=$1
    local user host

    case "$spec" in
    *@*@*)
        bu_log_err "Invalid remote spec[$spec]: expected [user@]host with at most one '@'"
        return 1
        ;;
    *@*)
        user=${spec%@*}
        host=${spec#*@}
        ;;
    *)
        __bu_remote_local_user
        user=$BU_RET
        host=$spec
        ;;
    esac

    if [[ -z "$user" ]]
    then
        bu_log_err "Invalid remote spec[$spec]: empty user part"
        return 1
    fi
    if [[ -z "$host" ]]
    then
        bu_log_err "Invalid remote spec[$spec]: empty host part"
        return 1
    fi
    if [[ ! "$user" =~ ^[A-Za-z0-9._-]+$ ]]
    then
        bu_log_err "Invalid remote user[$user] in spec[$spec]: only [A-Za-z0-9._-] allowed"
        return 1
    fi
    if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]
    then
        bu_log_err "Invalid remote host[$host] in spec[$spec]: only [A-Za-z0-9._-] allowed"
        return 1
    fi

    BU_RET_MAP[user]=$user
    BU_RET_MAP[host]=$host
    BU_RET="$user@$host"
    return 0
}

# The directory holding ControlMaster sockets (a helper so every consumer
# agrees on the same `$BU_REMOTE_SSH_DIR`/`$BU_OUT_DIR/ssh` resolution).
#
# @set BU_RET the ssh socket directory
# bash-ide parse-func-sig
__bu_remote_ssh_dir()
{
    BU_RET=${BU_REMOTE_SSH_DIR:-$BU_OUT_DIR/ssh}
}

# Compute the ControlMaster socket path for a spec: `<dir>/cm-<normalized>`.
#
# @arg $1 {string} spec spec
# @set BU_RET socket path
#
# @returns
# - Exit code 0 on success, 1 when the path exceeds ~100 bytes (unix
#   sun_path is 104/108 bytes and ssh fails obscurely past it)
# bash-ide parse-func-sig
bu_remote_socket()
{
    local -r spec=$1
    local normalized
    bu_remote_spec_normalize "$spec" || return 1
    normalized=$BU_RET

    local dir
    __bu_remote_ssh_dir
    dir=$BU_RET

    local sock=$dir/cm-$normalized
    if (( ${#sock} > 100 ))
    then
        bu_log_err "ControlMaster socket path[$sock] is ${#sock} bytes; the unix sun_path limit is ~100 bytes. Set BU_REMOTE_SSH_DIR to a shorter directory."
        return 1
    fi
    BU_RET=$sock
    return 0
}

# True when a live ControlMaster exists for the spec: the socket file exists
# AND `ssh -o ControlPath=<sock> -O check <spec>` succeeds.  The socket
# existence check comes first so a bare no-socket case never even spawns ssh
# (important for PATH-stub tests that count ssh invocations).
#
# @arg $1 {string} spec spec
#
# @returns Exit code 0 (alive) or 1 (not alive)
# bash-ide parse-func-sig
bu_remote_session_alive()
{
    local -r spec=$1
    local sock
    bu_remote_socket "$spec" || return 1
    sock=$BU_RET

    [[ -e "$sock" ]] || return 1
    ssh -o "ControlPath=$sock" -O check "$spec" &>/dev/null
}

# Resolve the master pid from `ssh -O check` stderr (e.g.
# `Master running (pid=1234)`).
#
# @arg $1 {string} spec spec
# @set BU_RET master pid
#
# @returns
# - Exit code 0 on success, 1 when the check fails or yields no pid
# bash-ide parse-func-sig
__bu_remote_master_pid()
{
    local -r spec=$1
    local sock out
    bu_remote_socket "$spec" || return 1
    sock=$BU_RET

    out=$(ssh -o "ControlPath=$sock" -O check "$spec" 2>&1) || return 1
    if [[ "$out" =~ pid=([0-9]+) ]]
    then
        BU_RET=${BASH_REMATCH[1]}
        return 0
    fi
    return 1
}

# Build the ssh options for a non-interactive command invocation: always
# `-o BatchMode=yes` (fail fast, never prompt), plus `-o ControlPath=<sock>`
# only when a master is already alive (sessions accelerate, never gate).
#
# @arg $1 {string} spec spec
# @arg $2 {var} out nameref to an array to populate
#
# @returns Exit code 0 on success
# bash-ide parse-func-sig
bu_remote_ssh_opts()
{
    local -r spec=$1
    local -n out=$2
    out=(-o BatchMode=yes)
    if bu_remote_session_alive "$spec"
    then
        local sock
        bu_remote_socket "$spec" || return 1
        sock=$BU_RET
        out+=(-o "ControlPath=$sock")
    fi
    return 0
}

# Default remote bootstrap (used when BU_REMOTE_BOOTSTRAP_CALLBACK is unset):
# defines `__bu_remote_dispatch()` as a thin wrapper over the CLI command
# name, then type-checks that the CLI is actually available remotely (rc
# files that activate the project provide it), erroring with guidance when
# it is not.
# bash-ide parse-func-sig
__bu_remote_default_bootstrap()
{
    local -r cli=$BU_CLI_COMMAND_NAME
    printf '__bu_remote_dispatch() { %s "$@"; }\n' "$cli"
    printf 'if ! command -v %s >/dev/null 2>&1; then\n' "$cli"
    printf '  echo "ERR: %s is not available on this host; activate the project in ~/.bashrc or register BU_REMOTE_BOOTSTRAP_CALLBACK" >&2\n' "$cli"
    printf '  exit 127\n'
    printf 'fi\n'
}

# Print the full remote payload for a spec.
#
# Preamble: `set -e`, then source /etc/profile and ~/.bashrc with stdout AND
# stderr silenced (rc-file chatter would otherwise corrupt the JSONL stream).
# Bootstrap: the BU_REMOTE_BOOTSTRAP_CALLBACK output (or the default) which
# activates the project and defines `__bu_remote_dispatch`.  When the
# optional array BU_REMOTE_BOOTSTRAP_OPTS is set, its elements are passed
# verbatim to the callback after the remote dir (the default bootstrap
# ignores them).  Body: command mode prints a %q-quoted
# `__bu_remote_dispatch <argv>` line; script mode wraps a block in
# `set +e; fn() { set -e; <block>; }; fn; exit $?` so one activation serves
# N commands.
#
# @arg $1 {string} remote_dir remote dir (passed to the bootstrap callback; may be empty)
# @arg $2 {string} mode `command` or `script`
# @arg $@ {string} args... command argv (command mode) or a single script block (script mode)
# @stdout the remote payload
# bash-ide parse-func-sig
bu_remote_build_script()
{
    local -r remote_dir=$1
    local -r mode=$2
    shift 2

    printf 'set -e\n'
    printf '. /etc/profile >/dev/null 2>&1 || true\n'
    printf '. ~/.bashrc >/dev/null 2>&1 || true\n'

    if [[ -n "${BU_REMOTE_BOOTSTRAP_CALLBACK:-}" ]]
    then
        "$BU_REMOTE_BOOTSTRAP_CALLBACK" "$remote_dir" ${BU_REMOTE_BOOTSTRAP_OPTS[@]+"${BU_REMOTE_BOOTSTRAP_OPTS[@]}"}
    else
        __bu_remote_default_bootstrap
    fi

    if [[ "$mode" == command ]]
    then
        printf '__bu_remote_dispatch'
        printf ' %q' "$@"
        printf '\n'
    else
        local block=${1-}
        printf 'set +e\nfn() { set -e\n%s\n}\nfn\nexit $?\n' "$block"
    fi
}

# True when a host is this machine (`localhost` or $HOSTNAME) so the runner
# can short-circuit to `env -i ... bash -s` instead of ssh.
#
# @arg $1 {string} host host
#
# @returns Exit code 0 (local) or 1 (not local)
# bash-ide parse-func-sig
__bu_remote_is_local_host()
{
    local -r host=$1
    [[ "$host" == localhost ]] && return 0
    [[ -n "${HOSTNAME:-}" && "$host" == "$HOSTNAME" ]] && return 0
    local hn
    hn=$(hostname 2>/dev/null) && [[ -n "$hn" && "$host" == "$hn" ]] && return 0
    return 1
}

# Run a marshaled payload on one or more hosts, sequentially.
#
# Local short-circuit: when the host is this machine (`localhost`/`$HOSTNAME`)
# and the user part is $USER, the payload runs through `env -i ... bash -s`
# with the same from-scratch environment semantics, no ssh dependency.
# Otherwise it runs `ssh <opts> <spec> bash -s`.
#
# stdout is tagged per-host: with inject=true each line passes through jq so
# JSON objects gain a `host` field (non-JSON passes verbatim); inject=false
# is a pure passthrough.  stderr is line-prefixed `[<spec>] `.  Each host's rc
# is captured; the overall rc is the last non-zero.  pipefail is enabled for
# this function only (the jq at the pipeline tail would otherwise mask remote
# failures) and restored on exit.
#
# @arg $1 {string} script_file script file to feed to `bash -s`
# @arg $2 {string} inject `true` to inject a host field, `false` for passthrough
# @arg $@ {string} args... specs
#
# @returns Exit code: last non-zero host rc (0 if all succeed)
# bash-ide parse-func-sig
bu_remote_invoke()
{
    local -r script_file=$1
    local -r inject=$2
    shift 2

    local had_pipefail=false
    [[ -o pipefail ]] && had_pipefail=true
    set -o pipefail

    local overall_rc=0
    local spec normalized user host rc
    local local_user
    __bu_remote_local_user
    local_user=$BU_RET
    local -a opts=()
    local -a stdout_filter=()
    for spec in "$@"
    do
        if ! bu_remote_spec_normalize "$spec"
        then
            overall_rc=1
            continue
        fi
        normalized=$BU_RET
        user=${BU_RET_MAP[user]}
        host=${BU_RET_MAP[host]}

        if [[ "$inject" == true ]]
        then
            stdout_filter=(jq -Rr --arg host "$normalized" "$BU_REMOTE_JQ_HOST_FILTER")
        else
            stdout_filter=(cat)
        fi

        rc=0
        if [[ "$user" == "$local_user" ]] && __bu_remote_is_local_host "$host"
        then
            env -i HOME="$HOME" USER="$local_user" PATH=/usr/bin:/bin bash -s \
                < "$script_file" \
                2> >(sed "s/^/[$normalized] /" >&2) \
                | "${stdout_filter[@]}" || rc=$?
        else
            opts=()
            bu_remote_ssh_opts "$normalized" opts || { rc=$?; overall_rc=$rc; continue; }
            ssh "${opts[@]}" "$normalized" bash -s \
                < "$script_file" \
                2> >(sed "s/^/[$normalized] /" >&2) \
                | "${stdout_filter[@]}" || rc=$?
        fi

        (( rc != 0 )) && overall_rc=$rc
    done

    if ! "$had_pipefail"
    then
        set +o pipefail
    fi

    return "$overall_rc"
}

# Remove one remote session: send `-O exit` when a master answers, else
# just clear the stale socket.  Emits one JSONL record with action
# `closed` (master was live), `removed-stale` (socket present, no master),
# or `absent` (no socket at all).
#
# @arg $1 {string} spec spec
#
# @returns Exit code 0 on success (including absent), 1 on an invalid spec
# bash-ide parse-func-sig
__bu_remote_remove_spec()
{
    local -r spec=$1
    local normalized sock action
    bu_remote_spec_normalize "$spec" || return 1
    normalized=$BU_RET
    bu_remote_socket "$spec" || return 1
    sock=$BU_RET

    if [[ ! -e "$sock" ]]
    then
        bu_out_record "host=$normalized" action=absent "socket=$sock"
        return 0
    fi

    if ssh -o "ControlPath=$sock" -O exit "$normalized" &>/dev/null
    then
        action=closed
    else
        action=removed-stale
    fi
    rm -f "$sock"
    bu_out_record "host=$normalized" "action=$action" "socket=$sock"
    return 0
}
