# Pipe metadata sidecars: let the reader of a pipe learn which pipeline wrote it.
#
# A pipe carries bytes, not metadata. But the kernel gives every pipe an inode,
# and both ends can see it: the writer's /proc/<pid>/fd/1 and the reader's
# /proc/<pid>/fd/0 are symlinks to the same `pipe:[<inode>]`. A small file
# keyed by that inode is therefore a side channel from writer to reader.
#
# Protocol
# --------
# Writer (every top-level `bu` dispatch whose stdout is a pipe, see
# __bu_impl): before the command runs, write
#
#     $BU_OUT_DIR/pipes/<out-pipe inode>
#
# holding three lines:
#
#     pgid <process group of the writer>
#     upstream <inode of the writer's stdin pipe, or empty>
#     stage bu <command> <args...>
#
# An argument that is empty or contains whitespace, `|`, a quote or a
# backslash is stored as `_`: the static analyzer reads a stage word by word
# and lineage depends only on clause structure (which fields a `select` keeps,
# what an `agg` computes), never on filter values. The key of a `key=value`
# argument is kept (`name=_`): for a recordifier it names an output field.
#
# Reader (`... | bu get-column`): read the first line of stdin (or EOF), then
# look up the sidecar for the fd 0 inode, prepend its stage, and follow
# `upstream` until a stage that is a producer (or standalone), an empty
# upstream, or 64 hops. The chain is the pipeline that produced stdin.
# A chain that ends at a missing sidecar is usable only when its earliest
# stage defines its own schema (`cat f | bu convert-from-tsv --columns a,b`).
#
# Ordering: a writer's sidecar is on disk before its command runs, so before
# any byte reaches the pipe; the reader has seen a byte (or EOF) before it
# resolves. A middle stage reads its own stdin before writing, so by the time
# its output arrives its upstream sidecar exists too.
#
# Staleness: inodes are recycled. A sidecar is accepted only when its pgid
# equals the reader's: the members of one pipeline share a process group, both
# under job control (one group per job) and in scripts (the script's group).
# The reader deletes the sidecars it consumed; the rest (a pipeline that had
# no bu reader) are reaped once older than an hour, on 1 write in 128 and on
# every resolve.
#
# Nesting: only depth-1 dispatches write (__BU_IMPL_DEPTH), so a command that
# calls `bu` internally leaves no sidecars for its private pipes.
#
# Cost: nothing when stdout is not a pipe (one `[[ -p ]]`); otherwise one
# `readlink` fork and one small file write per dispatch. Disable with
# BU_OUT_PIPE_METADATA=false. Without /proc (macOS) the writer is a no-op and
# the reader falls back to inferring columns from the records.

# *Description*:
# Process group of a process, read from /proc without forking.
#
# *Params*:
# - `$1`: pid
# - `$2`: name of the variable that receives the pgid (empty when unknown)
#
# *Returns*:
# - 1 when /proc/PID/stat cannot be read
__bu_pipemeta_pgid()
{
    local -n _pp_out=$2
    local _pp_line= _pp_state= _pp_ppid= _pp_pgrp= _pp_rest=
    _pp_out=
    [[ -r "/proc/$1/stat" ]] || return 1
    { IFS= read -r _pp_line < "/proc/$1/stat"; } 2>/dev/null
    [[ -n "$_pp_line" ]] || return 1
    # comm may itself contain spaces and parentheses: cut at the last ')'.
    # The fields after it are: state ppid pgrp ...
    _pp_line=${_pp_line##*) }
    read -r _pp_state _pp_ppid _pp_pgrp _pp_rest <<< "$_pp_line"
    [[ "$_pp_pgrp" =~ ^[0-9]+$ ]] || return 1
    _pp_out=$_pp_pgrp
    return 0
}

# *Description*:
# Delete sidecars older than an hour.
#
# *Params*:
# - `$1`: sidecar directory
__bu_pipemeta_reap()
{
    [[ -d "$1" ]] || return 0
    find "$1" -maxdepth 1 -type f -mmin +60 -delete 2>/dev/null
    return 0
}

# *Description*:
# Record the dispatched command as the writer of the stdout pipe. No-op unless
# stdout is a pipe and `BU_OUT_PIPE_METADATA` is true. Never fails.
#
# *Params*:
# - `$1`: command name (without the `bu` prefix)
# - `...`: its arguments
__bu_pipemeta_write()
{
    # The pipe test comes first: a non-piped dispatch pays only this.
    [[ -p /dev/stdout ]] || return 0
    [[ "${BU_OUT_PIPE_METADATA:-}" == true ]] || return 0
    [[ -n "${BU_OUT_DIR:-}" ]] || return 0
    # Capture the pid first: inside $(...) BASHPID is the substitution's own.
    local -r _pw_me=$BASHPID
    local -r _pw_dir=$BU_OUT_DIR/pipes
    local _pw_links= _pw_out= _pw_in= _pw_pgid= _pw_arg= _pw_stage=
    _pw_links=$(readlink "/proc/$_pw_me/fd/1" "/proc/$_pw_me/fd/0" 2>/dev/null)
    _pw_out=${_pw_links%%$'\n'*}
    [[ "$_pw_out" =~ ^pipe:\[([0-9]+)\]$ ]] || return 0
    _pw_out=${BASH_REMATCH[1]}
    if [[ "$_pw_links" == *$'\n'* && "${_pw_links#*$'\n'}" =~ ^pipe:\[([0-9]+)\]$ ]]
    then
        _pw_in=${BASH_REMATCH[1]}
    fi
    __bu_pipemeta_pgid "$_pw_me" _pw_pgid || return 0
    _pw_stage="bu $1"
    shift
    for _pw_arg in "$@"
    do
        if [[ -z "$_pw_arg" || "$_pw_arg" == *[[:space:]\|\'\"\\]* ]]
        then
            # Keep the key of key=value / key:=value: for a recordifier it
            # names an output field (bu new-record name='a b').
            if [[ "$_pw_arg" =~ ^([A-Za-z_][A-Za-z0-9_.-]*:?=) ]]
            then
                _pw_arg=${BASH_REMATCH[1]}_
            else
                _pw_arg=_
            fi
        fi
        _pw_stage+=" $_pw_arg"
    done
    [[ -d "$_pw_dir" ]] || mkdir -p "$_pw_dir" 2>/dev/null || return 0
    { printf 'pgid %s\nupstream %s\nstage %s\n' "$_pw_pgid" "$_pw_in" "$_pw_stage" > "$_pw_dir/$_pw_out"; } 2>/dev/null
    if (( RANDOM % 128 == 0 ))
    then
        # Every fd off the pipe, or the reader would wait on the reaper for EOF.
        # The enclosing subshell keeps an interactive shell from printing a job line.
        ( __bu_pipemeta_reap "$_pw_dir" </dev/null >/dev/null 2>&1 & )
    fi
    return 0
}

# *Description*:
# Read one sidecar.
#
# *Params*:
# - `$1`: sidecar file
# - `$2`: pgid the sidecar must carry
#
# *Returns*:
# - `$BU_RET`: `(stage upstream)`
# - 1 when the file is missing, has no stage, or its pgid differs
__bu_pipemeta_read()
{
    local _pr_key= _pr_value= _pr_pgid= _pr_upstream= _pr_stage=
    BU_RET=()
    [[ -f "$1" && -r "$1" ]] || return 1
    while IFS=' ' read -r _pr_key _pr_value || [[ -n "$_pr_key" ]]
    do
        case "$_pr_key" in
        pgid) _pr_pgid=$_pr_value ;;
        upstream) _pr_upstream=$_pr_value ;;
        stage) _pr_stage=$_pr_value ;;
        esac
    done < "$1"
    [[ -n "$_pr_stage" && -n "$2" && "$_pr_pgid" == "$2" ]] || return 1
    BU_RET=("$_pr_stage" "$_pr_upstream")
    return 0
}

# *Description*:
# Reconstruct the pipeline that writes this process's stdin from the sidecars.
# Call it after reading the first line of stdin (see the ordering note above).
# Consumed sidecars are deleted. Always returns 0.
#
# *Returns*:
# - `$BU_RET`: `(pipeline status)`. status is `resolved`, `none` (stdin is not
#   a pipe, or it has no sidecar) or `broken` (at least one sidecar resolved,
#   then an upstream one is missing: a `grep`/`jq` stage in the middle). A
#   missing upstream is not `broken` when the earliest known stage defines its
#   own schema (a recordifier, a transform, or a Columns-From function)
__bu_pipemeta_resolve()
{
    local -r _ps_me=$BASHPID
    local -r _ps_dir=${BU_OUT_DIR:-}/pipes
    local _ps_inode= _ps_pgid= _ps_pipeline= _ps_status=none _ps_effect= _ps_hops=0 _ps_file= _ps_from=
    local -a _ps_words=() _ps_consumed=()
    BU_RET=('' none)
    [[ -p /dev/stdin && -d "$_ps_dir" ]] || return 0
    _ps_inode=$(readlink "/proc/$_ps_me/fd/0" 2>/dev/null)
    # Take the inode out of BASH_REMATCH before anything else can overwrite it.
    if [[ "$_ps_inode" =~ ^pipe:\[([0-9]+)\]$ ]] && _ps_inode=${BASH_REMATCH[1]} \
        && __bu_pipemeta_pgid "$_ps_me" _ps_pgid
    then
        while (( _ps_hops < 64 ))
        do
            : $((_ps_hops++))
            _ps_file=$_ps_dir/$_ps_inode
            if ! __bu_pipemeta_read "$_ps_file" "$_ps_pgid"
            then
                # Missing upstream. That is fine when the earliest stage we
                # know defines its own schema (cat file | bu convert-from-tsv
                # --columns a,b): what fed it does not matter.
                if (( ${#_ps_consumed[@]} ))
                then
                    __bu_column_from_function "${_ps_words[1]:-}" _ps_from
                    case "$_ps_effect" in
                    recordify_*|transform) ;;
                    *) [[ -n "$_ps_from" ]] || _ps_status=broken ;;
                    esac
                fi
                break
            fi
            _ps_consumed+=("$_ps_file")
            _ps_pipeline=${BU_RET[0]}${_ps_pipeline:+ | $_ps_pipeline}
            _ps_status=resolved
            read -r -a _ps_words <<< "${BU_RET[0]}"
            __bu_out_stage_effect_lookup "${_ps_words[1]:-}" _ps_effect
            case "$_ps_effect" in
            producer|standalone) break ;;
            esac
            # Digits only: the value names a file we are about to read and delete.
            [[ "${BU_RET[1]}" =~ ^[0-9]+$ ]] || break
            _ps_inode=${BU_RET[1]}
        done
        (( ${#_ps_consumed[@]} )) && rm -f -- "${_ps_consumed[@]}" 2>/dev/null
    fi
    __bu_pipemeta_reap "$_ps_dir" </dev/null >/dev/null 2>&1
    BU_RET=("$_ps_pipeline" "$_ps_status")
    return 0
}
