#!/usr/bin/env bash

# Bash wrapper for the tree-sitter daemon.
#
# Uses bash coproc for bidirectional communication with the node daemon.
#
# Usage: source this file, then call bu_ts_parse CURSOR_OFFSET "COMMAND_LINE"
# Result stored in BU_TS_RESULT associative array.

# bash-ide source=../../bu_custom_source.sh


BU_TS_DAEMON=$BU_LIB_BIN_DIR/bu_ts_daemon.js
BU_TS_COPROC_PID=
BU_TS_TRAP_SET=

# Start the daemon via coproc if not running
# bash-ide parse-func-sig
__bu_ts_daemon_start()
{
    # Check if daemon is still alive
    if [[ -n "$BU_TS_COPROC_PID" ]] && kill -0 "$BU_TS_COPROC_PID" 2>/dev/null; then
        return 0
    fi

    # Clean up any stale coproc state from previous sourcing.
    # Closing the fds will cause the old node daemon to exit on EOF.
    if [[ -v BU_TS_COPROC ]]; then
        exec {BU_TS_COPROC[0]}>&- 2>/dev/null || true
        exec {BU_TS_COPROC[1]}>&- 2>/dev/null || true
        unset -v BU_TS_COPROC
    fi

    coproc BU_TS_COPROC { trap '' INT; node "$BU_TS_DAEMON"; }
    BU_TS_COPROC_PID=$!

    # Set exit trap once to clean up daemon on shell exit.
    # Main shell only (BASH_SUBSHELL): bash runs EXIT traps inside command
    # substitution subshells too — a subshell that starts the daemon (e.g.
    # result=$(simulate_selection ...)) would otherwise execute a chained
    # foreign trap (bats' result printer) at subshell exit. The subshell's
    # daemon needs no trap: its fds close at subshell exit and the node
    # process exits on stdin EOF.
    # Chain onto any existing EXIT trap instead of clobbering it: under bats,
    # the result line ("ok"/"not ok") is printed by bats' own EXIT trap —
    # clobbering it makes any failing test vanish from TAP output entirely
    # ("Executed N instead of M tests").
    if [[ -z "$BU_TS_TRAP_SET" && $BASH_SUBSHELL -eq 0 ]]; then
        local existing_trap
        existing_trap=$(trap -p EXIT)
        if [[ "$existing_trap" == "trap -- '"* ]]; then
            existing_trap=${existing_trap#trap -- \'}
            existing_trap=${existing_trap%\' EXIT}
            trap "bu_ts_daemon_stop; $existing_trap" EXIT
        else
            trap 'bu_ts_daemon_stop' EXIT
        fi
        BU_TS_TRAP_SET=1
    fi

    # Read the ready signal
    local ready
    IFS= read -r -t 3 -u "${BU_TS_COPROC[0]}" ready
    if [[ "$ready" != '{"ready":true}' ]]; then
        bu_log_err "tree-sitter daemon did not send ready signal: $ready"
        return 1
    fi
    bu_log_info "tree-sitter daemon started (pid=$BU_TS_COPROC_PID)"
    return 0
}

# Parse a command line with tree-sitter.
# $1: cursor offset (byte position)
# $2: command line string
# bash-ide parse-func-sig
bu_ts_parse()
{
    local -r cursor_offset=$1
    local -r command_line=$2

    __bu_ts_daemon_start || return 1

    printf '%s:%s\n' "$cursor_offset" "$command_line" >&"${BU_TS_COPROC[1]}"

    local response
    IFS= read -r -t 3 -u "${BU_TS_COPROC[0]}" response || {
        bu_log_err "tree-sitter daemon timeout"
        return 1
    }

    # Parse JSON response into key=value pairs using a single node invocation
    local parsed
    parsed=$(node -e '
        const r = JSON.parse(require("fs").readFileSync("/dev/stdin","utf8").trim());
        const out = [];
        for (const [k, v] of Object.entries(r)) {
            if (typeof v === "string" || typeof v === "boolean" || typeof v === "number")
                out.push(k + "=" + String(v));
        }
        if (r.cursor) {
            for (const [k, v] of Object.entries(r.cursor)) {
                out.push("cursor," + k + "=" + String(v));
            }
        }
        out.push("cmdWords=" + (r.cmdWords || []).join("\x1f"));
        console.log(out.join("\n"));
    ' <<<"$response" 2>/dev/null) || {
        bu_log_err "Failed to parse tree-sitter response"
        return 1
    }

    declare -g -A BU_TS_RESULT=()
    local line key value
    while IFS='=' read -r key value; do
        BU_TS_RESULT[$key]=$value
    done <<<"$parsed"

    return 0
}

# Stop the daemon
# bash-ide parse-func-sig
bu_ts_daemon_stop()
{
    if [[ -n "$BU_TS_COPROC_PID" ]]; then
        kill "$BU_TS_COPROC_PID" 2>/dev/null || true
        wait "$BU_TS_COPROC_PID" 2>/dev/null || true
        { exec {BU_TS_COPROC[0]}>&-; } 2>/dev/null || true
        { exec {BU_TS_COPROC[1]}>&-; } 2>/dev/null || true
        BU_TS_COPROC_PID=
        BU_TS_TRAP_SET=
        bu_log_info "tree-sitter daemon stopped"
    fi
}
