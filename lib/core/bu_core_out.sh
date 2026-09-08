# MARK: Structured output
# PowerShell-inspired structured output for bu commands.
#
# Data model: JSONL (one JSON object per line) is the "object pipeline".
# Commands produce records, transforms pass them through, and a sink
# formatter decides presentation at the end of the pipeline (Out-Default).
#
# Layers:
# - Recordifiers (raw -> JSONL): bu_out_record, bu_out_from_tsv, bu_out_from_lines
# - Sinks (JSONL -> display):    bu_format_table, bu_format_list,
#                                bu_format_json, bu_format_jsonl, bu_format_tsv
# - Dispatcher (Out-Default):    bu_out
#
# jq is the backend for record construction and formatting.
# Pipeline users can drop to raw jq at any point for Where-Object /
# Select-Object style filtering.

# bash-ide source=./bu_core_base.sh

# Resolved once at source time. Empty means jq is unavailable.
BU_OUT_JQ=$(command -v jq 2>/dev/null) || BU_OUT_JQ=

# Standard output formats for structured commands.
# Used by --format flags and Out-Default auto-detection.
BU_OUT_FORMATS=(auto table list json jsonl tsv)

# Preset pager shortcuts for BU_TABLE_PAGER.  Maps preset names (the part
# after "preset:") to full pager command lines.  Extend via
# bu_register_table_pager_preset.
declare -A -g __BU_TABLE_PAGER_PRESETS=(
    [less]="less -R"
    [less-quit]="less -FRSX"
    [bat]="bat --paging=always"
    [never]=cat
)

# ```
# *Description*:
# Register a preset pager shortcut for BU_TABLE_PAGER.
# Users can then write BU_TABLE_PAGER=preset:<name>.
#
# *Params*:
# - `$1`: Preset name (e.g. "less", "bat")
# - `$2`: Full pager command (e.g. "less -R", "bat --paging=always")
#
# *Examples*:
# ```bash
# bu_register_table_pager_preset "moar" "moar -style native"
# ```
# ```
bu_register_table_pager_preset()
{
    local name=$1
    local cmd=$2
    if [[ -z "$name" || -z "$cmd" ]]
    then
        bu_log_err "Usage: bu_register_table_pager_preset <name> <command>"
        return 1
    fi
    __BU_TABLE_PAGER_PRESETS[$name]=$cmd
}

# Table display styles for bu_format_table.  Each value is a JSON descriptor
# consumed by the jq renderer.  A "seg spec" ({left,char,join,right,min,pad})
# draws a horizontal rule whose per-column segment is `.width + 2*pad`
# characters (at least `min`).  `left`/`vsep`/`right` wrap data and header
# lines; `top`/`hsep`/`rsep`/`bottom` are optional seg specs (or null).
# `header_bold` bolds the header row (on a terminal only).  Extend via
# bu_register_table_style.
declare -A -g __BU_TABLE_STYLES=(
    [classic]='{"header_bold":true,"left":"","vsep":"  ","right":"","top":null,"hsep":{"left":"","char":"-","join":"  ","right":"","min":1,"pad":0},"rsep":null,"bottom":null}'
    [plain]='{"header_bold":false,"left":"","vsep":"  ","right":"","top":null,"hsep":null,"rsep":null,"bottom":null}'
    [ascii]='{"header_bold":true,"left":"| ","vsep":" | ","right":" |","top":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1},"hsep":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1},"rsep":null,"bottom":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1}}'
    [unicode]='{"header_bold":true,"left":"│ ","vsep":" │ ","right":" │","top":{"left":"┌","char":"─","join":"┬","right":"┐","min":1,"pad":1},"hsep":{"left":"├","char":"─","join":"┼","right":"┤","min":1,"pad":1},"rsep":null,"bottom":{"left":"└","char":"─","join":"┴","right":"┘","min":1,"pad":1}}'
    [double]='{"header_bold":true,"left":"║ ","vsep":" ║ ","right":" ║","top":{"left":"╔","char":"═","join":"╦","right":"╗","min":1,"pad":1},"hsep":{"left":"╠","char":"═","join":"╬","right":"╣","min":1,"pad":1},"rsep":null,"bottom":{"left":"╚","char":"═","join":"╩","right":"╝","min":1,"pad":1}}'
    [markdown]='{"header_bold":true,"left":"| ","vsep":" | ","right":" |","top":null,"hsep":{"left":"| ","char":"-","join":" | ","right":" |","min":3,"pad":0},"rsep":null,"bottom":null}'
    [mysql]='{"header_bold":true,"left":"| ","vsep":" | ","right":" |","top":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1},"hsep":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1},"rsep":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1},"bottom":{"left":"+","char":"-","join":"+","right":"+","min":1,"pad":1}}'
    [psql]='{"header_bold":true,"left":"","vsep":" | ","right":"","top":null,"hsep":{"left":"","char":"-","join":"+","right":"","min":1,"pad":0},"rsep":null,"bottom":null}'
    [clickhouse]='{"header_bold":true,"left":"│ ","vsep":" │ ","right":" │","top":{"left":"┌","char":"─","join":"┬","right":"┐","min":1,"pad":1},"hsep":null,"rsep":null,"bottom":{"left":"└","char":"─","join":"┴","right":"┘","min":1,"pad":1}}'
)

# ```
# *Description*:
# Register (or override) a table display style for bu_format_table.
# Users can then pass --style <name> or set BU_TABLE_STYLE=<name>.
#
# *Params*:
# - `$1`: Style name (e.g. "unicode", "markdown")
# - `$2`: JSON descriptor (see __BU_TABLE_STYLES for the shape)
#
# *Examples*:
# ```bash
# bu_register_table_style "fancy" '{"header_bold":true,"left":"","vsep":"  ","right":"","top":null,"hsep":{"left":"","char":"=","join":"  ","right":"","min":1,"pad":0},"rsep":null,"bottom":null}'
# ```
# ```
bu_register_table_style()
{
    local name=$1
    local descriptor=$2
    if [[ -z "$name" || -z "$descriptor" ]]
    then
        bu_log_err "Usage: bu_register_table_style <name> <json-descriptor>"
        return 1
    fi
    __BU_TABLE_STYLES[$name]=$descriptor
}

# Static field registry: producer command-line prefix -> space-separated
# record fields. Consulted first by __bu_out_complete_pipeline_fields when
# completing after a pipe. Longest prefix match wins.
#
# Prefer # Fields: annotations in the producer script header (parsed lazily
# and cached here on first use). This registry now only holds entries that
# cannot be expressed as a simple annotation: jc parser-dependent schemas,
# and a few core entries for zero-latency first-hit performance.
# Extend via bu_register_output_fields (e.g. from a module preinit script).
declare -A -g BU_OUT_PRODUCER_FIELDS=(
    # jc parser fields (registered by parser name for convert-from-jc)
    ["bu convert-from-jc --parser ls"]="filename flags links owner group size date"
    ["bu convert-from-jc --parser ps"]="user pid vsz rss tty stat start time command cpu_percent mem_percent"
    ["bu convert-from-jc --parser df"]="filesystem 1k_blocks used available mounted_on use_percent"
    ["bu convert-from-jc --parser dig"]="id opcode status flags query_num answer_num authority_num additional_num opt_pseudosection question answer query_time server when rcvd when_epoch when_epoch_utc"
    ["bu convert-from-jc --parser free"]="type total used free shared buff_cache available"
    ["bu convert-from-jc --parser mount"]="filesystem mount_point type options"
    ["bu convert-from-jc --parser uptime"]="time uptime users load_1m load_5m load_15m time_hour time_minute time_second uptime_days uptime_hours uptime_minutes uptime_total_seconds"
    ["bu convert-from-jc --parser uname"]="kernel_name node_name kernel_release operating_system processor hardware_platform machine kernel_version"
    ["bu convert-from-jc --parser env"]="name value"
    ["bu convert-from-jc --parser id"]="uid gid groups"
    ["bu convert-from-jc --parser du"]="size name"
    ["bu convert-from-jc --parser stat"]="file size blocks io_blocks type device inode links access flags uid user gid group access_time modify_time change_time birth_time access_time_epoch access_time_epoch_utc modify_time_epoch modify_time_epoch_utc change_time_epoch change_time_epoch_utc birth_time_epoch birth_time_epoch_utc"
    ["bu convert-from-jc --parser ifconfig"]="name flags state mtu type mac_addr ipv4_addr ipv4_mask ipv4_bcast ipv6_addr ipv6_mask ipv6_scope ipv6_type metric rx_packets rx_errors rx_dropped rx_overruns rx_frame tx_packets tx_errors tx_dropped tx_overruns tx_carrier tx_collisions rx_bytes tx_bytes ipv4"
    ["bu convert-from-jc --parser netstat"]="proto recv_q send_q local_address foreign_address state program_name kind local_port foreign_port transport_protocol network_protocol local_port_num"
    ["bu convert-from-jc --parser arp"]="name address hwtype hwaddress iface"
    ["bu convert-from-jc --parser dpkg-l"]="codes name version architecture description desired status"
    ["bu convert-from-jc --parser iostat"]="percent_user percent_nice percent_system percent_iowait percent_steal percent_idle type"
    ["bu convert-from-jc --parser vmstat"]="runnable_procs uninterruptible_sleeping_procs virtual_mem_used free_mem buffer_mem cache_mem inactive_mem active_mem swap_in swap_out blocks_in blocks_out interrupts context_switches user_time system_time idle_time io_wait_time stolen_time timestamp timezone"
    ["bu convert-from-jc --parser lsof"]="command pid user fd type device size_off node name"
    ["bu convert-from-jc --parser wc"]="filename lines words characters"
)

# Allowlist of producer head commands that may be executed ("probed") during
# autocompletion to discover fields from live output. Probing runs the
# user-typed pipeline prefix, so both this allowlist and the master switch
# BU_OUT_PROBE_PIPELINE are opt-in. Example:
#     BU_OUT_PROBE_COMMANDS[kubectl]=1
declare -A -g BU_OUT_PROBE_COMMANDS=()

# Per-producer opt-in for executing a producer during TAB completion to
# capture distinct field VALUES. Keyed by the canonicalized producer string
# (same "bu <command> ..." keys as BU_OUT_PRODUCER_FIELDS, longest-prefix
# matched so flags in the typed pipeline don't defeat the lookup).
#
# The declaration is a promise about cost and side effects: the command is
# read-only and returns promptly. State-changing or slow producers must
# never carry it. Prefer the `# Tab-Execute: true` header annotation
# (parsed lazily and cached here on first use) over central registration.
declare -A -g BU_OUT_TAB_EXECUTE=()

# Per-producer opt-in for executing a producer during TAB completion to
# discover FIELD NAMES (a bare <TAB> after a pipe). Independent from the
# value gate (BU_OUT_TAB_EXECUTE): field completion fires on a casual,
# exploratory post-pipe TAB, whereas the value position only fires after the
# user has typed a field and an equality operator, so a command author who
# accepted value-position execution has not necessarily accepted execution
# on every post-pipe TAB.
#
# Same promise and constraints as BU_OUT_TAB_EXECUTE (read-only, returns
# promptly; state-changing or slow producers must never carry it). Prefer the
# `# Tab-Execute-Field: true` header annotation (parsed lazily and cached
# here on first use) over central registration.
declare -A -g BU_OUT_TAB_EXECUTE_FIELD=()

# ```
# *Description*:
# Register a producer as safe to execute during TAB completion so its
# distinct field values can be offered at the where/query value position.
#
# *Params*:
# - `$1`: Producer command-line prefix (e.g. "bu get-command")
#
# *Examples*:
# ```bash
# bu_register_tab_execute "bu get-command"
# ```
# ```
bu_register_tab_execute()
{
    local producer=$1
    if [[ -z "$producer" ]]
    then
        bu_log_err "Usage: bu_register_tab_execute <producer-prefix>"
        return 1
    fi
    BU_OUT_TAB_EXECUTE[$producer]=1
}

# ```
# *Description*:
# Register a producer as safe to execute during TAB completion so its record
# field names can be discovered at the post-pipe field position.
#
# *Params*:
# - `$1`: Producer command-line prefix (e.g. "bu get-command")
#
# *Examples*:
# ```bash
# bu_register_tab_execute_field "bu get-command"
# ```
# ```
bu_register_tab_execute_field()
{
    local producer=$1
    if [[ -z "$producer" ]]
    then
        bu_log_err "Usage: bu_register_tab_execute_field <producer-prefix>"
        return 1
    fi
    BU_OUT_TAB_EXECUTE_FIELD[$producer]=1
}

# Record cap for tab-execute row capture: bounds producer cost even against
# unbounded sources; every field's completion reuses the same captured rows.
declare -g -r __BU_OUT_VALUE_RECORD_CAP=1000
# Distinct cap for a single field's value candidates: a high-cardinality
# column (e.g. an id) yields this many candidates plus the static hint, not
# a million.
declare -g -r __BU_OUT_VALUE_DISTINCT_CAP=50
# Session-scoped memo of captured producer rows, keyed by producer_str.
# No disk cache: datasets are live; re-source clears the memo.
declare -A -g __BU_OUT_TAB_ROWS=()

# ```
# *Description*:
# Assert that jq is available for structured output
#
# *Returns*:
# - Exit code 1 and logs an error if jq is not available
# ```
__bu_out_assert_jq()
{
    if [[ -z "$BU_OUT_JQ" ]]
    then
        bu_log_err "jq is required for bu structured output. Install jq (e.g. 'sudo apt install jq' / 'brew install jq')."
        return 1
    fi
}

# ```
# *Description*:
# Validate a record key. Keys become jq object keys in generated programs,
# so they must be plain identifiers.
#
# *Params*:
# - `$1`: Key to validate
#
# *Returns*:
# - Exit code 1 and logs an error if the key is invalid
# ```
__bu_out_validate_key()
{
    if [[ ! "$1" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]
    then
        bu_log_err "Invalid record key[$1]. Keys must match [a-zA-Z_][a-zA-Z0-9_]*"
        return 1
    fi
}

# ```
# *Description*:
# Parse a comma-separated column spec list, supporting optional display labels.
#
# *Params*:
# - `$1`: Comma-separated specs, each `key` or `key:Label`
#         (e.g. `name:Module,version,path:Location`). Empty string yields empty arrays.
#
# *Returns*:
# - `$BU_RET`: JSON array of keys (e.g. `["name","version","path"]`)
# - `$BU_RET_HEADERS`: JSON array of display labels, parallel to the keys
#                      (e.g. `["Module","version","Location"]`). Unlabeled keys
#                      use the key itself as the label.
#
# *Notes*:
# - Labels are display-only; lookups and --colors always use the key.
# - Keys must be identifiers (validated); labels may be any string.
# ```
__bu_out_parse_colspecs()
{
    local -a specs=()
    local spec
    local ifs=$IFS
    IFS=','
    # shellcheck disable=SC2206 # Intentional word splitting on commas
    specs=($1)
    IFS=$ifs
    local -a keys=() headers=()
    local key header
    for spec in "${specs[@]}"
    do
        [[ -z "$spec" ]] && continue
        key=${spec%%:*}
        header=${spec#*:}
        [[ -z "$header" ]] && header=$key
        __bu_out_validate_key "$key" || return 1
        keys+=("$key")
        headers+=("$header")
    done
    if ((${#keys[@]} == 0))
    then
        BU_RET='[]'
        BU_RET_HEADERS='[]'
    else
        BU_RET=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${keys[@]}")
        BU_RET_HEADERS=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${headers[@]}")
    fi
}

# ```
# *Description*:
# Convert a comma-separated column spec list to a JSON array of keys,
# silently dropping any `:Label` display labels.
#
# *Params*:
# - `$1`: Comma-separated specs (see __bu_out_parse_colspecs)
#
# *Returns*:
# - `$BU_RET`: JSON array of keys
# ```
__bu_out_cols_to_json()
{
    __bu_out_parse_colspecs "$@"
}

# ```
# *Description*:
# Convert a comma-separated column spec list to a JSON array of
# `{key, header}` objects for the display formatters.
#
# *Params*:
# - `$1`: Comma-separated specs (see __bu_out_parse_colspecs)
#
# *Returns*:
# - `$BU_RET`: JSON array (e.g. `[{"key":"name","header":"Module"},...]`)
# ```
__bu_out_colspecs_to_json()
{
    __bu_out_parse_colspecs "$@" || return 1
    local keys_json=$BU_RET
    if [[ "$keys_json" == '[]' ]]
    then
        BU_RET='[]'
        return 0
    fi
    BU_RET=$("$BU_OUT_JQ" -cn \
        --argjson keys "$keys_json" \
        --argjson headers "$BU_RET_HEADERS" \
        '[range(0; $keys | length) | {key: $keys[.], header: $headers[.]}]')
}

# Predefined palette for --colors auto (rotating rainbow).
# Keys: BU_TPUT_* color names (lowercase), in rotation order.
__BU_OUT_RAINBOW=(
    blue
    green
    yellow
    red
    violet
    vscode_orange
    vscode_pink
    dark_blue
)

# ```
# *Description*:
# Build a JSON color map from a comma-separated `key=color` spec
#
# *Params*:
# - `$1`: Comma-separated `key=color` pairs (e.g. `name=green,version=yellow`).
#         Colors map to BU_TPUT_* variables (e.g. `green` -> `$BU_TPUT_GREEN`).
#
# *Returns*:
# - `$BU_RET`: JSON object mapping keys to ANSI codes (e.g. `{"name":"\u001b[32m"}`)
# ```
__bu_out_colors_to_json()
{
    local spec=$1
    BU_RET='{}'
    [[ -z "$spec" ]] && return 0

    local -a pairs=()
    local ifs=$IFS
    IFS=','
    # shellcheck disable=SC2206 # Intentional word splitting on commas
    pairs=($spec)
    IFS=$ifs

    local -a kv=()
    local pair key color_name color_var
    for pair in "${pairs[@]}"
    do
        [[ -z "$pair" ]] && continue
        key=${pair%%=*}
        color_name=${pair#*=}
        __bu_out_validate_key "$key" || return 1
        color_var=BU_TPUT_${color_name^^}
        if [[ ! -v $color_var ]]
        then
            bu_log_err "Unknown color[$color_name] in --colors. Expected a BU_TPUT_* color name (e.g. green, yellow, bold)."
            return 1
        fi
        kv+=("$key" "${!color_var}")
    done
    if ((${#kv[@]}))
    then
        BU_RET=$("$BU_OUT_JQ" -cn --args \
            'reduce range(0; $ARGS.positional | length; 2) as $i ({}; .[$ARGS.positional[$i]] = $ARGS.positional[$i + 1])' \
            -- "${kv[@]}")
    fi
}

# ```
# *Description*:
# Get the terminal width for table layout
#
# *Returns*:
# - `$BU_RET`: Terminal width in columns (defaults to 80 if undetectable)
# ```
__bu_out_term_width()
{
    BU_RET=${COLUMNS:-}
    if [[ -z "$BU_RET" ]]
    then
        BU_RET=$(tput cols 2>/dev/null)
    fi
    if [[ -z "$BU_RET" ]] || (( BU_RET < 20 ))
    then
        BU_RET=80
    fi
}

# MARK: Recordifiers (raw -> JSONL)

# ```
# *Description*:
# Construct a single JSON record (one line of JSONL) from key=value pairs.
# Values are properly JSON-escaped via jq --arg.
#
# *Params*:
# - `...`: `key=value` pairs. Use `key:=value` for typed JSON values
#          (numbers, booleans, arrays) via jq --argjson.
#
# *Returns*:
# - stdout: One JSON object on a single line
#
# *Examples*:
# ```bash
# bu_out_record name=bashtab version=0.1.0
# # {"name":"bashtab","version":"0.1.0"}
#
# bu_out_record pid=$$ alive:=true retries:=3
# # {"pid":"12345","alive":true,"retries":3}
# ```
#
# *Notes*:
# - Forks one jq process per call. For loops over many records, prefer
#   emitting TSV and converting once with `bu_out_from_tsv`.
# ```
bu_out_record()
{
    __bu_out_assert_jq || return 1

    local -a jq_args=()
    local prog= sep=
    local pair key value i=0
    for pair in "$@"
    do
        case "$pair" in
        *:=*)
            key=${pair%%:=*}
            value=${pair#*:=}
            __bu_out_validate_key "$key" || return 1
            jq_args+=(--argjson "v$i" "$value")
            ;;
        *=*)
            key=${pair%%=*}
            value=${pair#*=}
            __bu_out_validate_key "$key" || return 1
            jq_args+=(--arg "v$i" "$value")
            ;;
        *)
            bu_log_err "Expected key=value or key:=value, got[$pair]"
            return 1
            ;;
        esac
        prog+="$sep\"$key\":\$v$i"
        sep=,
        # `: $((i++))`, not bare `((i++))`: the bare form returns 1 when the
        # post-increment evaluates to 0, which aborts callers under `set -e`.
        : $((i++))
    done
    "$BU_OUT_JQ" -cn "${jq_args[@]}" "{$prog}"
}

# ```
# *Description*:
# Convert a TSV stream to JSONL in a single jq process (stream recordifier).
# This is the preferred pattern for loops: printf TSV per record (zero forks),
# then recordify the whole stream at once.
#
# *Params*:
# - `--columns a,b,c`: Comma-separated column names, assigned to TSV fields in order
# - stdin: Tab-separated lines. Fields without a column are dropped;
#          missing trailing fields leave keys absent. Blank lines are skipped.
#
# *Returns*:
# - stdout: JSONL stream
#
# *Examples*:
# ```bash
# printf 'bashtab\t0.1.0\nmyapp\t-\n' | bu_out_from_tsv --columns name,version
# # {"name":"bashtab","version":"0.1.0"}
# # {"name":"myapp","version":"-"}
# ```
#
# *Notes*:
# - Values must not contain tabs or newlines. For arbitrary strings, use
#   `bu_out_record` per record instead.
# ```
bu_out_from_tsv()
{
    __bu_out_assert_jq || return 1

    local columns=
    local shift_by=1
    while (($#))
    do
        case "$1" in
        --columns)
            columns=$2
            shift_by=2
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_out_from_tsv"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done
    if [[ -z "$columns" ]]
    then
        bu_log_err "bu_out_from_tsv requires --columns"
        return 1
    fi

    __bu_out_cols_to_json "$columns" || return 1
    local cols_json=$BU_RET

    "$BU_OUT_JQ" -R -c --argjson cols "$cols_json" '
        select(. != "")
        | split("\t")
        | reduce to_entries[] as $e ({};
            if $cols[$e.key] != null then .[$cols[$e.key]] = $e.value else . end)
    '
}

# ```
# *Description*:
# Convert a line-oriented stream to JSONL, one single-key record per line.
# Useful for wrapping line-oriented tools (ls, git, ...) into records.
#
# *Params*:
# - `--column name`: Key to assign each line to (required)
# - stdin: Lines of text
#
# *Returns*:
# - stdout: JSONL stream
#
# *Examples*:
# ```bash
# printf 'a.txt\nb.txt\n' | bu_out_from_lines --column file
# # {"file":"a.txt"}
# # {"file":"b.txt"}
# ```
bu_out_from_lines()
{
    __bu_out_assert_jq || return 1

    local column=
    local shift_by=1
    while (($#))
    do
        case "$1" in
        --column)
            column=$2
            shift_by=2
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_out_from_lines"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done
    if [[ -z "$column" ]]
    then
        bu_log_err "bu_out_from_lines requires --column"
        return 1
    fi
    __bu_out_validate_key "$column" || return 1

    "$BU_OUT_JQ" -R -c --arg k "$column" '{($k): .}'
}

# MARK: Transforms (JSONL -> JSONL)

# ```
# *Description*:
# Filter a JSONL stream with a jq boolean expression (PowerShell Where-Object).
# Streams record-by-record with O(1) latency.
#
# *Params*:
# - `$1`: jq expression evaluated per record; records where it is truthy pass.
#         The current record is `.` (e.g. `.version == "-"`, `.name | test("^bu")`).
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: Filtered JSONL stream
#
# *Examples*:
# ```bash
# bu get-command | bu_out_where '.type == "source"'
# ```
#
# *Notes*:
# - The expression is embedded into a jq program verbatim (same trust
#   boundary as writing raw jq).
# ```
bu_out_where()
{
    __bu_out_assert_jq || return 1
    if (($# != 1))
    then
        bu_log_err "bu_out_where expects exactly one jq expression"
        return 1
    fi
    "$BU_OUT_JQ" -c "select($1)"
}

# --------------------------------------------------------------------------
# Operator-to-jq translation helpers (for PowerShell-style --where syntax)
# --------------------------------------------------------------------------

# ```
# *Description*:
# Convert a user-supplied value to a jq literal. Numbers, booleans, and null
# are passed through as-is; everything else is quoted as a jq string.
#
# *Params*:
# - `$1`: Raw value string (unquoted at the shell level, e.g. source, 42,
#         "hello world" if the user typed quotes)
#
# *Returns*:
# - stdout: The value as a valid jq literal
#
# *Examples*:
# ```bash
# __bu_jq_literal 42        # 42
# __bu_jq_literal true      # true
# __bu_jq_literal null      # null
# __bu_jq_literal hello     # "hello"
# __bu_jq_literal "hi,there" # "hi,there"  (shell-stripped quotes, re-quoted)
# ```
# ```
__bu_jq_literal()
{
    local val=$1

    # null
    if [[ "$val" == null ]]; then printf 'null'; return 0; fi
    # booleans
    if [[ "$val" == true || "$val" == false ]]; then printf '%s' "$val"; return 0; fi
    # signed integer or float (includes negative)
    if [[ "$val" =~ ^-?[0-9]+\.?[0-9]*$ || "$val" =~ ^-?[0-9]*\.[0-9]+$ ]]; then
        # Must not be empty string or just "-"
        if [[ "$val" != - && "$val" != "" ]]; then
            printf '%s' "$val"; return 0
        fi
    fi

    # String: escape backslashes and double quotes, then wrap in double quotes
    local escaped=${val//\\/\\\\}
    escaped=${escaped//\"/\\\"}
    printf '"%s"' "$escaped"
}

# ```
# *Description*:
# Report whether a value produced by `__bu_jq_literal` is a jq *number*
# literal (as opposed to a quoted string, `true`, `false`, or `null`).
#
# *Params*:
# - `$1`: A jq literal string as emitted by `__bu_jq_literal`
#
# *Returns*:
# - exit 0 when the literal is numeric, 1 otherwise
# ```
__bu_jq_literal_is_numeric()
{
    local lit=$1
    [[ "$lit" =~ ^-?[0-9]+\.?[0-9]*$ || "$lit" =~ ^-?[0-9]*\.[0-9]+$ ]]
}

# ```
# *Description*:
# Convert a shell glob pattern to a jq-compatible regex for the `test`
# function.  Handles `*` (any chars), `?` (one char), escapes everything
# else that is a regex metacharacter.
#
# *Params*:
# - `$1`: Glob pattern (e.g. "*.txt", "get-?")
#
# *Returns*:
# - stdout: Regex string suitable for jq's `test()`
#
# *Examples*:
# ```bash
# __bu_glob_to_regex "*.sh"   # ^.*\.sh$
# __bu_glob_to_regex "get-?"  # ^get-.$
# ```
# ```
__bu_glob_to_regex()
{
    local glob=$1
    local regex=
    local i ch
    for (( i = 0; i < ${#glob}; i++ )); do
        ch=${glob:i:1}
        case "$ch" in
        '\\') regex+='\\\\' ;;
        '.')   regex+='\\.' ;;
        '*')   regex+='.*' ;;
        '?')   regex+='.' ;;
        '['|']'|'('|')'|'{'|'}'|'^'|'$'|'+'|'|')
                regex+='\\'$ch ;;
        *)     regex+=$ch ;;
        esac
    done
    printf '^%s$' "$regex"
}

# ```
# *Description*:
# Translate a PowerShell-style structured comparison to a jq boolean
# expression string suitable for `bu_out_where` (or the --where clause of
# `bu query-object`).
#
# *Params*:
# - `$1`: Field name (e.g. `type`, `name` — no leading dot)
# - `$2`: Operator: one of -eq -ne -gt -lt -ge -le -like -notlike -match
#         -notmatch -contains -notcontains -in -notin -isnull -isnotnull
# - `$3`: Value (empty for -isnull / -isnotnull). For -in / -notin this is a
#         comma-separated list: each element is literalized independently
#         (numbers/booleans/null keep their type, strings are quoted) and the
#         comparison becomes a jq `IN(...)` set-membership test. A value that
#         contains a literal comma cannot be expressed this way — use the raw
#         jq syntax instead.
#
#         Numeric coercion: when the literalized RHS of a scalar comparison
#         (-eq -ne -gt -lt -ge -le) is a jq number, the FIELD is wrapped as
#         `(.field | tonumber? // .)` before comparing, so string-typed
#         numeric fields (e.g. `{"channel":"1108"}`) match numeric RHS values.
#         Non-numeric fields fall back to themselves unchanged. For -in/-notin
#         the same wrap is applied only when ANY list element is numeric; an
#         all-string list keeps the plain `.field` form. String RHS values
#         never trigger coercion.
#
# *Returns*:
# - stdout: jq boolean expression, e.g. `.type == "source"`
# - exit 0 on success, 1 if operator is unknown or the -in/-notin list is empty
#
# *Examples*:
# ```bash
# __bu_query_object_translate_op type -eq source       # .type == "source"
# __bu_query_object_translate_op channel -eq 1108      # (.channel | tonumber? // .) == 1108
# __bu_query_object_translate_op name -like "*.sh"     # .name | test("^.*\\.sh$")
# __bu_query_object_translate_op name -like command    # .name | test("^.*command.*$") (no wildcard => substring)
# __bu_query_object_translate_op name -match "^get-"   # .name | test("^get-")
# __bu_query_object_translate_op verb -isnull           # .verb == null
# __bu_query_object_translate_op type -in source,alias # .type | IN("source","alias")
# __bu_query_object_translate_op type -notin source,alias # .type | IN("source","alias") | not
# ```
# ```
__bu_query_object_translate_op()
{
    local field=$1
    local op=$2
    local val=$3
    local jq_expr=

    case "$op" in
    -eq|-ne|-gt|-lt|-ge|-le)
        # Scalar ordered/equality comparisons. When the literalized RHS is a
        # jq *number*, coerce the field through `tonumber? // .` so a
        # string-typed numeric field (e.g. `{"channel":"1108"}`) still
        # compares correctly. A genuinely non-numeric field value falls back
        # to itself, preserving jq's existing cross-type ordering semantics.
        local cmp_lit
        local field_ref
        cmp_lit=$(__bu_jq_literal "$val")
        if __bu_jq_literal_is_numeric "$cmp_lit"
        then
            field_ref="(.$field | tonumber? // .)"
        else
            field_ref=".$field"
        fi
        case "$op" in
        -eq) jq_expr="$field_ref == $cmp_lit" ;;
        -ne) jq_expr="$field_ref != $cmp_lit" ;;
        -gt) jq_expr="$field_ref > $cmp_lit" ;;
        -lt) jq_expr="$field_ref < $cmp_lit" ;;
        -ge) jq_expr="$field_ref >= $cmp_lit" ;;
        -le) jq_expr="$field_ref <= $cmp_lit" ;;
        esac
        ;;
    -like|-notlike)
        # PowerShell-flavored -like: a value with no glob wildcard
        # implies *value* (substring match), not exact match. Explicit
        # wildcards keep fully-anchored semantics (e.g. "get-*" means
        # "starts with get-"; "?" counts as a wildcard).
        local glob=$val
        if [[ "$glob" != *'*'* && "$glob" != *'?'* ]]
        then
            glob="*$glob*"
        fi
        local regex; regex=$(__bu_glob_to_regex "$glob")
        local regex_lit; regex_lit=$(__bu_jq_literal "$regex")
        if [[ "$op" == -like ]]
        then
            jq_expr=".$field | test($regex_lit)"
        else
            jq_expr=".$field | test($regex_lit) | not"
        fi
        ;;
    -match)
        local re_lit; re_lit=$(__bu_jq_literal "$val")
        jq_expr=".$field | test($re_lit)"
        ;;
    -notmatch)
        local re_lit; re_lit=$(__bu_jq_literal "$val")
        jq_expr=".$field | test($re_lit) | not"
        ;;
    -contains)
        local val_lit; val_lit=$(__bu_jq_literal "$val")
        jq_expr=".$field | index($val_lit) != null"
        ;;
    -notcontains)
        local val_lit; val_lit=$(__bu_jq_literal "$val")
        jq_expr=".$field | index($val_lit) == null"
        ;;
    -in|-notin)
        # PowerShell-flavored -in/-notin: the RHS is a comma-separated list
        # (set membership), not a scalar. Split on commas without glob
        # expansion, literalize each element independently (numbers, booleans,
        # and null keep their types; strings get quoted), and emit a jq
        # `IN(...)` membership test. A single element degenerates to a
        # one-element IN(...). Empty elements (leading/trailing/doubled
        # commas) are dropped.
        local -a elems=()
        local elem
        local item_lit
        local items=
        local has_numeric=false
        local field_ref
        IFS=',' read -r -a elems <<< "$val"
        for elem in "${elems[@]}"
        do
            [[ -z "$elem" ]] && continue
            item_lit=$(__bu_jq_literal "$elem")
            if __bu_jq_literal_is_numeric "$item_lit"
            then
                has_numeric=true
            fi
            if [[ -z "$items" ]]
            then
                items=$item_lit
            else
                items+=",$item_lit"
            fi
        done
        if [[ -z "$items" ]]
        then
            bu_log_err "Empty -in/-notin value[$val] for __bu_query_object_translate_op"
            return 1
        fi
        # If ANY element is numeric, coerce the field so string-typed numeric
        # fields match. All-string lists keep the plain `.field` form.
        if [[ "$has_numeric" == true ]]
        then
            field_ref="(.$field | tonumber? // .)"
        else
            field_ref=".$field"
        fi
        jq_expr="$field_ref | IN($items)"
        if [[ "$op" == -notin ]]
        then
            jq_expr+=" | not"
        fi
        ;;
    -isnull)    jq_expr=".$field == null" ;;
    -isnotnull) jq_expr=".$field != null" ;;
    *)
        bu_log_err "Unknown operator[$op] for __bu_query_object_translate_op"
        return 1
        ;;
    esac

    printf '%s' "$jq_expr"
}

# ```
# *Description*:
# Build the jq boolean expression for `bu query-object grep`: true when the
# pattern matches ANY top-level field value of a record (a grep of the row).
# Each value is stringified first (`tostring`), so numbers, booleans, and null
# participate too (e.g. grep "42" matches {"count":42}).
#
# *Params*:
# - `$1`: Match mode: regex | iregex | glob | iglob
#         - regex/iregex: pattern is a regex (case-sensitive / insensitive)
#         - glob/iglob:   PowerShell -like glob semantics — `*`/`?` wildcards
#           are anchored; a bare pattern with no wildcard means substring
#           (case-sensitive / insensitive)
# - `$2`: Pattern string
#
# *Returns*:
# - stdout: jq boolean expression, e.g.
#   `[.[] | tostring] | any(test("^get-.*$"))`
# - exit 0 on success
#
# *Examples*:
# ```bash
# __bu_query_object_translate_grep regex '^get-'   # any value matches the regex
# __bu_query_object_translate_grep glob command    # any value contains "command"
# __bu_query_object_translate_grep iglob 'GET-*'   # case-insensitive glob
# ```
# ```
__bu_query_object_translate_grep()
{
    local mode=$1
    local pattern=$2
    local re=$pattern

    case "$mode" in
    glob|iglob)
        # PowerShell-flavored -like: a value with no glob wildcard
        # implies *value* (substring match), not exact match.
        local glob=$pattern
        if [[ "$glob" != *'*'* && "$glob" != *'?'* ]]
        then
            glob="*$glob*"
        fi
        re=$(__bu_glob_to_regex "$glob")
        ;;
    esac

    local re_lit=${re//\\/\\\\}
    re_lit=${re_lit//\"/\\\"}
    case "$mode" in
    iregex|iglob)
        printf '[.[] | tostring] | any(test("%s"; "i"))' "$re_lit"
        ;;
    *)
        printf '[.[] | tostring] | any(test("%s"))' "$re_lit"
        ;;
    esac
}

# ```
# *Description*:
# Project a JSONL stream to a subset of fields, reordering and optionally
# renaming them (PowerShell Select-Object).
#
# *Params*:
# - `$1`: Comma-separated field specs. `name` keeps the field as-is;
#         `new=old` renames field `old` to `new`.
# - `--unique` (optional): Deduplicate records after projection (first
#         occurrence wins, order preserved). Equivalent to piping through
#         `bu_out_distinct` after the select.
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: JSONL stream containing only the selected fields
#
# *Examples*:
# ```bash
# bu get-command | bu_out_select name,type
# bu get-module | bu_out_select name,ver=version
# bu get-command | bu_out_select verb --unique
# ```
#
# *Notes*:
# - Field order in the spec determines key order in the output records.
# - Missing fields are emitted as null.
# ```
bu_out_select()
{
    __bu_out_assert_jq || return 1

    local is_unique=false
    local is_expand=false
    local field_spec=
    while (($#))
    do
        case "$1" in
        --unique)
            is_unique=true
            ;;
        --expand)
            is_expand=true
            ;;
        *)
            if [[ -n "$field_spec" ]]
            then
                bu_log_err "bu_out_select got an unexpected extra argument[$1]"
                return 1
            fi
            field_spec=$1
            ;;
        esac
        shift
    done
    if [[ -z "$field_spec" ]]
    then
        bu_log_err "bu_out_select expects a comma-separated field spec (e.g. 'name,ver=version')"
        return 1
    fi

    if "$is_expand"
    then
        # ExpandProperty: lift a single nested object to top level.
        # "select server --expand" on {"server":{"host":"x"}} → {"host":"x"}
        # No renaming or multiple fields allowed in expand mode.
        if [[ "$field_spec" == *,* || "$field_spec" == *\=* ]]
        then
            bu_log_err "bu_out_select --expand only accepts a single field (e.g. 'server'), got[$field_spec]"
            return 1
        fi
        if "$is_unique"
        then
            "$BU_OUT_JQ" -c ".$field_spec // empty" | bu_out_distinct
        else
            "$BU_OUT_JQ" -c ".$field_spec // empty"
        fi
        return $?
    fi

    local -a specs=()
    local ifs=$IFS
    IFS=','
    # shellcheck disable=SC2206 # Intentional word splitting on commas
    specs=($field_spec)
    IFS=$ifs

    local prog= sep=
    local spec new old
    for spec in "${specs[@]}"
    do
        [[ -z "$spec" ]] && continue
        case "$spec" in
        *=*)
            new=${spec%%=*}
            old=${spec#*=}
            __bu_out_validate_key "$new" || return 1
            __bu_out_validate_key "$old" || return 1
            ;;
        *)
            new=$spec
            old=$spec
            __bu_out_validate_key "$new" || return 1
            ;;
        esac
        prog+="$sep\"$new\":.$old"
        sep=,
    done
    if [[ -z "$prog" ]]
    then
        bu_log_err "bu_out_select got an empty field spec"
        return 1
    fi

    if "$is_unique"
    then
        "$BU_OUT_JQ" -c "{$prog}" | bu_out_distinct
    else
        "$BU_OUT_JQ" -c "{$prog}"
    fi
}

# ```
# *Description*:
# Sort a JSONL stream by a field (PowerShell Sort-Object). Buffers all input.
# jq ordering rules apply: null < false < true < numbers < strings < arrays < objects.
#
# *Params*:
# - `$1`: Field to sort by
# - `--desc` (optional): Sort descending
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: Sorted JSONL stream
#
# *Examples*:
# ```bash
# bu get-command | bu_out_sort_by noun
# bu get-command | bu_out_sort_by name --desc
# ```
bu_out_sort_by()
{
    __bu_out_assert_jq || return 1

    local key=
    local is_desc=false
    while (($#))
    do
        case "$1" in
        --desc)
            is_desc=true
            ;;
        *)
            if [[ -n "$key" ]]
            then
                bu_log_err "bu_out_sort_by got an unexpected extra argument[$1]"
                return 1
            fi
            key=$1
            ;;
        esac
        shift
    done
    if [[ -z "$key" ]]
    then
        bu_log_err "bu_out_sort_by requires a field to sort by"
        return 1
    fi
    __bu_out_validate_key "$key" || return 1

    if "$is_desc"
    then
        "$BU_OUT_JQ" -sc --arg key "$key" 'sort_by(.[$key]) | reverse | .[]'
    else
        "$BU_OUT_JQ" -sc --arg key "$key" 'sort_by(.[$key]) | .[]'
    fi
}

# ```
# *Description*:
# Remove duplicate records from a JSONL stream (SELECT DISTINCT /
# Select-Object -Unique). The first occurrence wins; original order is
# preserved (unlike group-by, which sorts by key). Records are compared
# with key-order canonicalization, so {"a":1,"b":2} equals {"b":2,"a":1}.
# Streams emission (first occurrences appear with O(1) latency); memory
# grows with the number of distinct records seen, which is inherent to dedupe.
#
# *Params*:
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: JSONL stream without duplicate records
#
# *Examples*:
# ```bash
# bu get-command | bu_out_select verb | bu_out_distinct
# ```
bu_out_distinct()
{
    __bu_out_assert_jq || return 1
    "$BU_OUT_JQ" -cn '
        def canon: if type == "object" then to_entries | sort_by(.key) | map({key: .key, value: (.value | canon)}) | from_entries
                   elif type == "array" then map(canon) else . end;
        foreach inputs as $r ({seen: {}};
            ($r | canon | tostring) as $k
            | if .seen[$k] then . + {emit: false} else (.seen[$k] = 1) + {emit: true} end;
            select(.emit) | $r)
    '
}

# MARK: Sinks (JSONL -> display)

# Shared jq prelude for the display formatters.
# - cellstr: null/missing -> "", strings as-is, everything else -> tostring
# - pad($w): right-pad with spaces to width $w
# - ellipsize($w): truncate to width $w with a trailing ellipsis
read -r -d '' __BU_OUT_JQ_PRELUDE <<'EOF' || :
def cellstr: if . == null then "" elif type == "string" then . else tostring end;
def ansistrip: gsub("\u001b[^a-zA-Z]*[a-zA-Z]"; "");
def ansilen: ansistrip | length;
def pad($w): . + " " * ($w - ansilen);
def ellipsize($w): if ansilen > $w then .[0:($w - ($ellipsis | length))] + $ellipsis else . end;
def rtrim: sub(" +$"; "");
# Table-style rendering helpers.  A style object has {header_bold,left,vsep,
# right,top,hsep,rsep,bottom}; top/hsep/rsep/bottom are "seg specs"
# ({left,char,join,right,min,pad}) or null.  Widths are measured in display
# columns via ansilen so borders align around ANSI-coloured cells.
def __table_seg($spec; $s):
    $s.left
    + ($spec | map(([$s.min, (.width + 2 * $s.pad)] | max) as $w | $s.char * $w) | join($s.join))
    + $s.right;
def __table_headercell($s; $bold; $reset):
    ($s.header | cellstr | ellipsize($s.width)) as $v
    | $bold + $v + $reset + (" " * ($s.width - ($v | ansilen)));
def __table_datacell($r; $s; $colors; $reset):
    ($r[$s.key] | cellstr | ellipsize($s.width)) as $v
    | ($colors[$s.key] // "") + $v + (if $colors[$s.key] then $reset else "" end)
    + (" " * ($s.width - ($v | ansilen)));
# Emit buffered rows (rsep between rows, bottom after the last), for the
# buffered renderer.
def __table_rows($spec; $style; $colors; $reset; $rows):
    ( $rows
      | to_entries[]
      | .value as $r
      | (if ($style.rsep and .key > 0) then __table_seg($spec; $style.rsep) else empty end),
        ($style.left + ($spec | map(__table_datacell($r; .; $colors; $reset)) | join($style.vsep)) + $style.right | rtrim)
    ),
    (if $style.bottom and ($rows | length) > 0 then __table_seg($spec; $style.bottom) else empty end);
EOF

# ```
# *Description*:
# Render a JSONL stream as an aligned table (PowerShell Format-Table).
#
# *Params*:
# - `--columns a,b,c`: Columns to display, in order. Each entry may carry a
#                      display label as `key:Label` (e.g. `name:Module`).
#                      Default: keys of the first record (insertion order).
#                      Required with --stream.
# - `--stream`:        Stream rows as they arrive using proportional column
#                      widths derived from the terminal width, instead of
#                      buffering all records for optimal auto-widths.
# - `--colors k=color,...`: Colorize column cells (see __bu_out_colors_to_json)
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: Header row, separator row, then one aligned row per record.
#           Empty input produces no output (PowerShell semantics).
#
# *Notes*:
# - Default mode buffers all input (jq slurp) to compute optimal column
#   widths, then shrinks the widest columns until the table fits the
#   terminal width (ellipsis truncation). This mirrors Format-Table -AutoSize.
# - The header is bold when stdout is a terminal.
# ```
bu_format_table()
{
    __bu_out_assert_jq || return 1

    local columns=
    local colors=
    local style=
    local is_stream=false
    local shift_by=1
    while (($#))
    do
        shift_by=1
        case "$1" in
        --columns)
            columns=$2
            shift_by=2
            ;;
        --colors)
            colors=$2
            shift_by=2
            ;;
        --style)
            style=$2
            shift_by=2
            ;;
        --stream)
            is_stream=true
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_format_table"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done

    [[ -n "$style" ]] || style=${BU_TABLE_STYLE:-classic}
    local style_json=${__BU_TABLE_STYLES[$style]:-}
    if [[ -z "$style_json" ]]
    then
        bu_log_err "Unknown table style[$style]; valid styles: ${!__BU_TABLE_STYLES[*]}"
        return 1
    fi

    __bu_out_colspecs_to_json "$columns" || return 1
    local cols_json=$BU_RET
    local rainbow_json='[]'
    if [[ "$colors" == auto ]]
    then
        # Build a JSON array of ANSI escape codes from the palette names
        local -a _ansi_palette=()
        local _cname _cvar
        for _cname in "${__BU_OUT_RAINBOW[@]}"
        do
            _cvar=BU_TPUT_${_cname^^}
            _ansi_palette+=("${!_cvar}")
        done
        rainbow_json=$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${_ansi_palette[@]}")
        __bu_out_colors_to_json ""  # validate, produce empty
        colors_json='{}'
    else
        __bu_out_colors_to_json "$colors" || return 1
        colors_json=$BU_RET
    fi
    __bu_out_term_width
    local termw=$BU_RET

    # Bold header on terminals only; reset always needed when colours are active
    local bold= reset=$BU_TPUT_RESET
    if [[ -t 1 ]]
    then
        bold=$BU_TPUT_BOLD
    fi
    # Suppress reset only when neither bold nor colours are emitted, so plain
    # (piped, uncoloured) output stays clean while a bold header on a terminal
    # is always reset before the separator/border.
    if [[ -z "$bold" && -z "$colors" && "$rainbow_json" == '[]' ]]
    then
        reset=
    fi

    # Pager support: when BU_TABLE_PAGER is set and stdout is a terminal,
    # pipe table output through the configured pager.
    # - "preset:less"   → resolves to "less -R" (or whatever the preset maps to)
    # - "less -R"       → used verbatim as a custom pager command
    # - "" (empty)      → no paging (cat passthrough)
    # Falls back to cat if the pager command is invalid or not found.
    local __bu_pager_pipe=cat
    if [[ -n "${BU_TABLE_PAGER:-}" && -t 1 ]]
    then
        if [[ "$BU_TABLE_PAGER" == preset:* ]]
        then
            local __bu_preset_name=${BU_TABLE_PAGER#preset:}
            if [[ -n "${__BU_TABLE_PAGER_PRESETS[$__bu_preset_name]:-}" ]]
            then
                __bu_pager_pipe=${__BU_TABLE_PAGER_PRESETS[$__bu_preset_name]}
            else
                bu_log_warn "Unknown pager preset[$__bu_preset_name]; valid presets: ${!__BU_TABLE_PAGER_PRESETS[*]}"
            fi
        else
            __bu_pager_pipe=$BU_TABLE_PAGER
        fi
    fi

    if "$is_stream"
    then
        if [[ "$cols_json" == '[]' ]]
        then
            bu_log_err "bu_format_table --stream requires --columns (cannot inspect the first record without buffering)"
            return 1
        fi
        "$BU_OUT_JQ" -rn \
            --argjson cols "$cols_json" \
            --argjson colors "$colors_json" \
            --argjson rainbow "$rainbow_json" \
            --argjson style "$style_json" \
            --argjson termw "$termw" \
            --argjson minw 4 \
            --arg bold "$bold" --arg reset "$reset" --arg ellipsis "…" \
            "$__BU_OUT_JQ_PRELUDE"'
            (if ($rainbow | length) > 0 then
               reduce range(0; $cols | length) as $i ({};
                   .[$cols[$i].key] = $rainbow[$i % ($rainbow | length)])
             else $colors end) as $colors
            | ($cols | length) as $n
            | (($style.left | length) + ($style.right | length) + ($style.vsep | length) * ($n - 1)) as $over
            | ([$cols[] | {key: .key, header: .header, width: ([$minw, ((($termw - $over) / $n) | floor)] | max)}]) as $spec
            | (if $style.header_bold then $bold else "" end) as $B
            | (if $style.top then __table_seg($spec; $style.top) else empty end),
              ($style.left + ($spec | map(__table_headercell(.; $B; $reset)) | join($style.vsep)) + $style.right | rtrim),
              (if $style.hsep then __table_seg($spec; $style.hsep) else empty end),
              (foreach inputs as $r (0; . + 1;
                   . as $i
                   | (if ($style.rsep and $i > 1) then __table_seg($spec; $style.rsep) else empty end),
                     ($style.left + ($spec | map(__table_datacell($r; .; $colors; $reset)) | join($style.vsep)) + $style.right | rtrim)
              )),
              (if $style.bottom then __table_seg($spec; $style.bottom) else empty end)
            ' | $__bu_pager_pipe || cat
        return
    fi

    "$BU_OUT_JQ" -s -r \
        --argjson cols "$cols_json" \
        --argjson colors "$colors_json" \
        --argjson rainbow "$rainbow_json" \
        --argjson style "$style_json" \
        --argjson termw "$termw" \
        --arg bold "$bold" --arg reset "$reset" --arg ellipsis "…" \
        "$__BU_OUT_JQ_PRELUDE"'
        . as $rows
        | if ($rows | length) == 0 and ($cols | length) == 0 then empty
        else
        ($cols | if length == 0 then $rows[0] | keys_unsorted | map({key: ., header: .}) else . end) as $cols
        | (if ($rainbow | length) > 0 then
             reduce range(0; $cols | length) as $i ({};
                 .[$cols[$i].key] = $rainbow[$i % ($rainbow | length)])
           else $colors end) as $colors
        | ([4, (if ($cols | length) > 10 then 6 elif ($cols | length) > 6 then 5 else 4 end)] | max) as $minw
        | ($cols | map(. as $c | {key: $c.key, header: $c.header, width: ([($c.header | length)] + [$rows[] | .[$c.key] | cellstr | ansilen] | max)})) as $init
        | def fit($spec; $style):
              (($style.left | length) + ($style.right | length)
               + ($style.vsep | length) * (($spec | length) - 1)) as $over
              | if ($spec | length) <= 1 then $spec
                elif (($spec | map(.width) | add) + $over) <= $termw then $spec
                elif ($spec | all(.[]; .width <= $minw)) then
                    # Even at min widths the table overflows — drop rightmost columns
                    fit($spec[:-1]; $style)
                else
                    # Shrink the widest column that is above the minimum
                    ($spec | map(select(.width > $minw)) | max_by(.width) | .key) as $mk
                    | fit($spec | map(if .key == $mk then .width -= 1 else . end); $style)
                end;
        fit($init; $style) as $spec
        | (if ($spec | length) < ($cols | length) then
              # Emit a short diagnostic to stderr when columns are dropped.
              # WARNING: do NOT pipe . through debug — 0-arity debug() dumps
              # the entire dataset (thousands of records) to stderr.  Use the
              # (msg | debug | empty), . pattern for jq 1.6 compat instead.
              (("table " + (($cols | length) - ($spec | length) | tostring) + " column(s) hidden (terminal too narrow); use --format tsv/jsonl for all fields" | debug | empty), .)
           else . end)
        | (if $style.header_bold then $bold else "" end) as $B
        | (if $style.top then __table_seg($spec; $style.top) else empty end),
          ($style.left + ($spec | map(__table_headercell(.; $B; $reset)) | join($style.vsep)) + $style.right | rtrim),
          (if $style.hsep then __table_seg($spec; $style.hsep) else empty end),
          __table_rows($spec; $style; $colors; $reset; $rows)
        end
        ' | $__bu_pager_pipe || cat
}

# ```
# *Description*:
# Render a JSONL stream as a list of key-value blocks (PowerShell Format-List).
# Streams record-by-record with O(1) latency.
#
# *Params*:
# - `--columns a,b,c`: Fields to display, in order. Each entry may carry a
#                      display label as `key:Label` (e.g. `name:Module`).
#                      Default: keys of each record.
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: `key : value` lines per record, separated by blank lines
#
# *Examples*:
# ```bash
# echo '{"name":"bashtab","version":"0.1.0"}' | bu_format_list
# # name    : bashtab
# # version : 0.1.0
# ```
bu_format_list()
{
    __bu_out_assert_jq || return 1

    local columns=
    local shift_by=1
    while (($#))
    do
        case "$1" in
        --columns)
            columns=$2
            shift_by=2
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_format_list"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done

    __bu_out_colspecs_to_json "$columns" || return 1
    local cols_json=$BU_RET

    "$BU_OUT_JQ" -r \
        --argjson cols "$cols_json" \
        "$__BU_OUT_JQ_PRELUDE"'
        . as $r
        | ($cols | if length == 0 then $r | keys_unsorted | map({key: ., header: .}) else . end) as $cs
        | ($cs | map(.header | length) | max) as $lw
        | ($cs | map(. as $c | ($c.header | pad($lw)) + " : " + ($r[$c.key] | cellstr)) | join("\n")),
          ""
        '
}

# ```
# *Description*:
# Render a JSONL stream as a pretty-printed JSON array (ConvertTo-Json).
# Buffers all input.
#
# *Params*:
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: JSON array
# ```
bu_format_json()
{
    __bu_out_assert_jq || return 1
    "$BU_OUT_JQ" -s .
}

# ```
# *Description*:
# Normalize a JSONL stream (compact, one validated object per line).
# Pure passthrough with O(1) latency.
#
# *Params*:
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: JSONL stream
# ```
bu_format_jsonl()
{
    __bu_out_assert_jq || return 1
    "$BU_OUT_JQ" -c .
}

# ```
# *Description*:
# Render a JSONL stream as TSV for scripting. Streams record-by-record.
# Embedded tabs/newlines in values are escaped by jq @tsv.
#
# *Params*:
# - `--columns a,b,c`: Fields to emit, in order. Default: keys of each record.
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: Tab-separated lines (no header row)
# ```
bu_format_tsv()
{
    __bu_out_assert_jq || return 1

    local columns=
    local shift_by=1
    while (($#))
    do
        case "$1" in
        --columns)
            columns=$2
            shift_by=2
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_format_tsv"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done

    __bu_out_cols_to_json "$columns" || return 1
    local cols_json=$BU_RET

    "$BU_OUT_JQ" -r \
        --argjson cols "$cols_json" \
        "$__BU_OUT_JQ_PRELUDE"'
        . as $r
        | ($cols | if length == 0 then $r | keys_unsorted else . end) as $cs
        | [$cs[] as $c | $r[$c] | cellstr] | @tsv
        '
}

# ```
# *Description*:
# Group a JSONL stream by one or more key fields, emitting one flat record
# per group (SQL GROUP BY with aggregates). Buffers all input (jq slurp).
#
# *Params*:
# - `--keys a[,b]`: Group key fields (comma-separated; composite key)
# - `--agg spec`:   Aggregate spec, repeatable AND comma-separated:
#                   `[name=]func[:field]`
#                   - `count`          group size
#                   - `sum:f`/`avg:f`  numeric only (non-numbers ignored)
#                   - `min:f`/`max:f`  non-null values, jq total ordering
#                   - `first:f`/`last:f`  by pipeline order
#                   - `collect:f`      array of the field's values
#                   Default output name: `count`, or `func_field` (e.g. `avg_hp`)
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: One JSON record per group: key fields + aggregate fields.
#           Records missing a key field form a null-key group.
#           Empty input produces no output.
#
# *Examples*:
# ```bash
# bu get-command --format jsonl | bu_out_group_by --keys verb --agg count
# bu get-pokemon --format jsonl | bu_out_group_by --keys type --agg count,avg:hp,total=sum:hp
# # No --agg: emits distinct key combinations (SQL SELECT DISTINCT)
# ```
bu_out_group_by()
{
    __bu_out_assert_jq || return 1

    local keys=
    local -a agg_specs=()
    local shift_by=1
    while (($#))
    do
        case "$1" in
        --keys)
            keys=$2
            shift_by=2
            ;;
        --agg)
            local spec ifs=$IFS
            IFS=','
            # shellcheck disable=SC2206 # Intentional word splitting on commas
            for spec in $2; do [[ -n "$spec" ]] && agg_specs+=("$spec"); done
            IFS=$ifs
            shift_by=2
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_out_group_by"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done
    if [[ -z "$keys" ]]
    then
        bu_log_err "bu_out_group_by requires --keys"
        return 1
    fi
    __bu_out_cols_to_json "$keys" || return 1
    local keys_json=$BU_RET

    # Generate one jq fragment per aggregate spec
    local fragments= sep=
    local name body func field fragment
    for spec in "${agg_specs[@]}"
    do
        case "$spec" in
        *=*) name=${spec%%=*}; body=${spec#*=} ;;
        *)   name=; body=$spec ;;
        esac
        func=${body%%:*}
        field=${body#*:}
        [[ "$field" == "$body" ]] && field=
        [[ -z "$name" ]] && name=$func${field:+_$field}
        __bu_out_validate_key "$name" || return 1
        case "$func" in
        count|sum|avg|min|max|first|last|collect) ;;
        *)
            bu_log_err "Unknown aggregate func[$func] in spec[$spec]. Expected one of: count, sum, avg, min, max, first, last, collect"
            return 1
            ;;
        esac
        if [[ "$func" != count ]]
        then
            if [[ -z "$field" ]]
            then
                bu_log_err "Aggregate[$spec] requires a field (e.g. $func:hp)"
                return 1
            fi
            __bu_out_validate_key "$field" || return 1
        fi
        # Note: \$g and \$v are jq variables, they must not be expanded by bash
        case "$func" in
        count)   fragment="(\$g | length)" ;;
        sum)     fragment="(\$g | map(.[\"$field\"]) | map(select(type == \"number\")) | add // 0)" ;;
        avg)     fragment="((\$g | map(.[\"$field\"]) | map(select(type == \"number\"))) as \$v | if (\$v | length) > 0 then (\$v | add) / (\$v | length) else null end)" ;;
        min)     fragment="(\$g | map(.[\"$field\"]) | map(select(. != null)) | min)" ;;
        max)     fragment="(\$g | map(.[\"$field\"]) | map(select(. != null)) | max)" ;;
        first)   fragment="(\$g[0][\"$field\"])" ;;
        last)    fragment="(\$g[-1][\"$field\"])" ;;
        collect) fragment="(\$g | map(.[\"$field\"]))" ;;
        esac
        fragments+="$sep\"$name\": $fragment"
        sep=,
    done

    "$BU_OUT_JQ" -sc --argjson keys "$keys_json" '
        group_by([.[$keys[]]])
        | map( . as $g
            | (reduce ($keys | to_entries[]) as $e ({}; .[$e.value] = $g[0][$e.value]))
            + {'"$fragments"'}
        )
        | .[]
    '
}

# MARK: Pipeline field completion

# ```
# *Description*:
# Register the record fields that a producer command emits, enabling
# pipeline-aware field completion after a pipe (e.g. in bu select).
#
# *Params*:
# - `$1`: Producer command-line prefix (e.g. `bu get-pokemon`, `kubectl get pods`)
# - `...`: Field names in record order
#
# *Examples*:
# ```bash
# bu_register_output_fields "bu get-pokemon" name id type hp attack
# ```
# ```
bu_register_output_fields()
{
    local -r producer=$1
    shift
    if [[ -z "$producer" || $# == 0 ]]
    then
        bu_log_err "Usage: bu_register_output_fields <producer-prefix> <field...>"
        return 1
    fi
    local field
    for field
    do
        __bu_out_validate_key "$field" || return 1
    done
    BU_OUT_PRODUCER_FIELDS[$producer]="$*"
}

# ```
# *Description*:
# Autocomplete helper (used via the `--ret` DSL): suggest record fields based
# on the pipeline preceding the cursor (PowerShell-style pipeline awareness).
#
# Field sources, in order:
# 1. Static registry `BU_OUT_PRODUCER_FIELDS` (longest prefix match on the
#    producer pipeline, so flags and later stages don't break the match)
# 2. Opt-in probing: when `BU_OUT_PROBE_PIPELINE=true` and the producer head
#    is in `BU_OUT_PROBE_COMMANDS`, the producer is executed as typed and the
#    keys of its first JSONL record are used
#
# *Params*:
# - `--dot` (optional): Prefix suggestions with `.` for jq-style expressions
#           (e.g. `.name`), used by bu where
# - `$1`: Current word being completed (appended by the --ret DSL)
#
# *Returns*:
# - `$BU_RET`: Candidate completions. Comma-aware: completing `name,ve`
#              yields `name,version`, ... excluding already-used fields.
#
# *Notes*:
# - Producer resolution order: `command_line_front_before_pipe` (fzf binding),
#   then `pipe_before` (tree-sitter binding), then a `COMP_WORDS` walk, then
#   a `COMP_LINE`/`COMP_POINT` scan. All are read via dynamic scope from the
#   completion machinery.
# - The COMP_WORDS fallback requires the pipe as a standalone word (`a | b`).
# - The COMP_LINE fallback covers the plain bash completion path (fzf binding
#   disabled), where COMP_WORDS only contains the post-pipe segment.
# ```
bu_complete_delimited()
{
    local delim=,
    local -a options=()

    while (($#))
    do
        case "$1" in
        --delimiter)
            delim=$2
            shift 2
            ;;
        --options)
            shift
            while (($#)) && [[ "$1" != --* ]]
            do
                options+=("$1")
                shift
            done
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    local cur_word=${1:-}
    BU_RET=()
    ((${#options[@]})) || return 1

    local prefix=
    local -A used=()
    local last_seg=$cur_word
    if [[ "$cur_word" == *"$delim"* ]]
    then
        prefix=${cur_word%"$delim"*}${delim}
        last_seg=${cur_word##*"$delim"}
        local used_token
        local ifs=$IFS
        IFS="$delim"
        for used_token in ${cur_word%"$delim"*}
        do
            [[ -n "$used_token" ]] && used[$used_token]=1
        done
        IFS=$ifs
    fi

    local opt
    for opt in "${options[@]}"
    do
        [[ -n "${used[$opt]:-}" ]] && continue
        [[ "$opt" == "$last_seg"* ]] && \
            BU_RET+=("${prefix}${opt}")
    done

    ((${#BU_RET[@]})) && return 0 || return 1
}

# ```
# *Description*:
# Generate completions from a Fig spec JSON file.  Walks the spec tree
# matching the command-line tokens against subcommands and options, then
# emits completions for what can come next: subcommands, options, or
# templated arguments (filepaths, folders).
#
# Designed for use with `bu_parse_positional --ret`.
#
# *Params*:
# - `--spec <path>`: Path to a Fig .json spec file
# - remaining arg: the current word (injected by `--ret`)
# - The full command line is read from `COMP_WORDS` / `COMP_CWORD` or
#   from the dynamically-scoped `command_line` array.
#
# *Returns*:
# - `$BU_RET`: Array of completions
# - exit 0 on success, 1 otherwise
#
# *Examples*:
# ```bash
# # In a command script that wraps a Fig-spec'd tool:
# bu_parse_positional $# --ret bu_complete_from_fig --spec "$HOME/.fig/act.json" -- ret-- \
#     --hint "arg"
# ```
# ```
bu_complete_from_fig()
{
    local spec_path=

    while (($#))
    do
        case "$1" in
        --spec)
            spec_path=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            break
            ;;
        esac
    done

    [[ -f "$spec_path" ]] || return 1
    local cur_word=${1:-}
    BU_RET=()

    # Build the token list from the command line.  Prefer the dynamically-
    # scoped `command_line` array (set by the fzf completion bindings),
    # otherwise fall back to COMP_WORDS / COMP_CWORD.
    local -a tokens=()
    local token_idx=0
    local i
    if [[ -n "${command_line[*]:-}" ]]
    then
        tokens=("${command_line[@]}")
        # Remove the command name (first token)
        tokens=("${tokens[@]:1}")
        # The last token is the current word; we already have cur_word
        ((${#tokens[@]})) && unset 'tokens[-1]'
    elif [[ -n "${COMP_WORDS[*]:-}" ]]
    then
        tokens=("${COMP_WORDS[@]:1:$COMP_CWORD-1}")
    fi

    # Walk the spec tree: find the deepest matching subcommand node
    local node_json
    node_json=$("$BU_OUT_JQ" -c --argjson tokens "$("$BU_OUT_JQ" -cn --args '$ARGS.positional' -- "${tokens[@]}")" '
    def walk($node; $tokens):
        if ($tokens | length) == 0 then $node
        else
            ($node.subcommands // []) as $subs
            | ($subs | map(select(.name == $tokens[0]))) as $matches
            | if ($matches | length) > 0 then
                walk($matches[0]; $tokens[1:])
              else $node end
        end;
    walk(.; $tokens)
    ' "$spec_path" 2>/dev/null) || return 1

    # Now generate completions from the matched node
    local -a completions=()

    # Check if the previous token is an option that takes arguments with a
    # template; if so, complete files/dirs for that template only.
    local prev_token=
    local prev_has_template=
    if ((${#tokens[@]}))
    then
        prev_token=${tokens[-1]}
        # Find the option in the node where name matches prev_token
        prev_has_template=$("$BU_OUT_JQ" -r --arg pt "$prev_token" '
            [.options[]? | select((.name | if type == "array" then .[] else . end) == $pt)]
            | .[0].args.template? | if type == "array" then .[] else . end // empty
        ' <<<"$node_json" 2>/dev/null)
    fi

    if [[ -n "$prev_has_template" ]]
    then
        # Complete files/dirs for the previous option'\''s template
        local tpl
        for tpl in $prev_has_template
        do
            case "$tpl" in
            filepaths)
                mapfile -t completions < <(compgen -f -- "$cur_word" 2>/dev/null)
                ;;
            folders)
                mapfile -t completions < <(compgen -d -- "$cur_word" 2>/dev/null)
                ;;
            esac
        done
        ((${#completions[@]})) || return 1
        BU_RET=("${completions[@]}")
        return 0
    fi

    # Build a name→description map from the matched node for metadata
    declare -A -g BU_FIG_METADATA_MAP=()
    local _fig_tsv
    _fig_tsv=$("$BU_OUT_JQ" -r '
        (.subcommands[]? | (.name | if type == "array" then .[] else . end) + "\t" + (.description // ""))
        ,
        (.options[]? | (.name | if type == "array" then .[] else . end) + "\t" + (.description // ""))
    ' <<<"$node_json" 2>/dev/null)
    if [[ -n "$_fig_tsv" ]]
    then
        local _fig_line _fig_name _fig_desc
        while IFS=$'\t' read -r _fig_name _fig_desc
        do
            [[ -n "$_fig_name" ]] && BU_FIG_METADATA_MAP[$_fig_name]=$_fig_desc
        done <<<"$_fig_tsv"
    fi

    # 1. Subcommands (handle array names like ["autoremove","auto-remove"])
    local sub_names
    sub_names=$("$BU_OUT_JQ" -r '.subcommands[]?.name | if type == "array" then .[] else . end // empty' <<<"$node_json" 2>/dev/null)
    if [[ -n "$sub_names" ]]
    then
        while IFS= read -r name
        do
            [[ "$name" == "$cur_word"* ]] && completions+=("$name")
        done <<<"$sub_names"
    fi

    # 2. Options (always show alongside subcommands, or alone if cur starts with -)
    local opt_entries
    opt_entries=$("$BU_OUT_JQ" -c '.options[]? // empty' <<<"$node_json" 2>/dev/null)
    if [[ -n "$opt_entries" ]]
    then
        while IFS= read -r opt
        do
            local opt_names
            opt_names=$("$BU_OUT_JQ" -r '.name | if type == "array" then .[] else . end' <<<"$opt" 2>/dev/null)
            while IFS= read -r oname
            do
                [[ -z "$oname" ]] && continue
                [[ "$oname" == "$cur_word"* ]] && completions+=("$oname")
            done <<<"$opt_names"
        done <<<"$opt_entries"
    fi

    # 3. Positional argument templates (only when no subcommand/option match
    #    and we have at least one token, or explicitly when cur starts without -)
    if ((${#completions[@]} == 0)) && [[ ! "$cur_word" == -* ]]
    then
        local arg_templates
        arg_templates=$("$BU_OUT_JQ" -r '.args[]?.template? | if type == "array" then .[] else . end // empty' <<<"$node_json" 2>/dev/null)
        if [[ -n "$arg_templates" ]]
        then
            local tpl
            for tpl in $arg_templates
            do
                case "$tpl" in
                filepaths)
                    local -a files
                    mapfile -t files < <(compgen -f -- "$cur_word" 2>/dev/null)
                    completions+=("${files[@]}")
                    ;;
                folders)
                    local -a dirs
                    mapfile -t dirs < <(compgen -d -- "$cur_word" 2>/dev/null)
                    completions+=("${dirs[@]}")
                    ;;
                esac
            done
        fi
    fi

    ((${#completions[@]})) || return 1
    BU_RET=("${completions[@]}")
    return 0
}

# ```
# *Description*:
# Bash completion function backed by a Fig spec.  Conforms to the standard
# bash completion interface (command, cur_word, prev_word) and populates
# COMPREPLY.  Used as a fallback when no native bash completion exists.
#
# *Params*:
# - `$1`: Command name (used to locate the Fig spec JSON file)
# - `$2`: Current word being completed
# - `$3`: Previous word (unused, but required by the completion interface)
#
# *Globals*:
# - Reads `command_line` (dynamically scoped from fzf bindings) or
#   `COMP_WORDS` / `COMP_CWORD` to reconstruct the full token list.
# - Sets `COMPREPLY` directly for bash'\''s completion machinery.
#
# *Spec lookup*: `$BU_FIG_SPEC_DIR/<command>.json`
# ```

# BashTab root directory, captured at definition time for Fig spec lookups
__BU_FIG_ROOT=$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null)

__bu_autocomplete_fig_completion_func()
{
    local cmd=$1 cur_word=$2
    local root="${BU_BASH_TAB_HOME:-${__BU_FIG_ROOT}}"
    local spec_path="${BU_FIG_SPEC_DIR:-${root}/fig_specs/build}/${cmd}.json"
    [[ -f "$spec_path" ]] || return 1

    local -a results
    bu_complete_from_fig --spec "$spec_path" -- "$cur_word" || return 1
    COMPREPLY=("${BU_RET[@]}")

    # Populate metadata from Fig spec descriptions
    if ((${#COMPREPLY[@]}))
    then
        local _i _c _desc
        for ((_i = 0; _i < ${#COMPREPLY[@]}; _i++))
        do
            _c=${COMPREPLY[_i]}
            _desc=${BU_FIG_METADATA_MAP[$_c]:-}
            if [[ -n "$_desc" ]]
            then
                BU_COMPREPLY_METADATA[_i]="${BU_TPUT_GREY}${_desc}${BU_TPUT_RESET}"
            fi
        done
    fi

    # Supplement with options from --help parsing when the Fig spec is
    # sparse (e.g. ls has only --color as a long option, missing --all).
    if bu_symbol_is_function __bu_help_parse_get 2>/dev/null
    then
        declare -A _fig_supp_opts=()
        if __bu_help_parse_get "$cmd" _fig_supp_opts 2>/dev/null && ((${#_fig_supp_opts[@]}))
        then
            local -A _fig_supp_seen=()
            local _c
            for _c in "${COMPREPLY[@]}"; do _fig_supp_seen[$_c]=1; done
            local _k
            for _k in "${!_fig_supp_opts[@]}"
            do
                if [[ "$_k" == "$cur_word"* ]] && [[ -z "${_fig_supp_seen[$_k]:-}" ]]
                then
                    COMPREPLY+=("$_k")
                fi
            done
        fi
    fi

    return 0
}

# ```
# *Description*:
# Autocompletion helper for pipeline producer fields.
# Resolves the field names emitted by the upstream producer in a pipeline
# and emits comma-aware completions suitable for --columns, --select, etc.
#
# *Params*:
# - `--dot` (optional flag): Prefix each field with a dot (for jq expressions)
# - `$1`: The current word being completed
#
# *Returns*:
# - `$BU_RET`: Array of completions
# - exit 0 on success, 1 if no producer could be resolved
#
# *Notes*:
# - Producer resolution order: `command_line_front_before_pipe` (fzf binding),
#   then `pipe_before` (tree-sitter binding), then a `COMP_WORDS` walk, then
#   a `COMP_LINE`/`COMP_POINT` scan. All are read via dynamic scope from the
#   completion machinery.
# - The COMP_WORDS fallback requires the pipe as a standalone word (`a | b`).
# - The COMP_LINE fallback covers the plain bash completion path (fzf binding
#   disabled), where COMP_WORDS only contains the post-pipe segment.
# ```
# ```
# *Description*:
# Recover the producer pipeline from the raw command line. Used as a last
# resort by `__bu_out_resolve_producer` in the plain bash completion path
# (fzf binding disabled), where bash hands the completion function only the
# command segment after the last pipe, so neither the binding locals nor
# COMP_WORDS can see the producer.
#
# Scans `${COMP_LINE:0:COMP_POINT}` for the last unquoted, single `|` and
# returns everything before it (cut at any earlier unquoted `;`, `&&`, `||`,
# `&` segment separator). Quote- and backslash-aware, but not
# command-substitution-aware: a pipe inside `$( )` may misresolve, in which
# case downstream registry matching simply finds no fields.
#
# *Returns*:
# - `$BU_RET`: Producer pipeline text (trimmed)
# - `$BU_RET_EVAL`: Same text, eval-able as typed
# - exit 0 on success, 1 if no usable pipe was found
# ```
__bu_out_resolve_producer_from_comp_line()
{
    BU_RET=
    BU_RET_EVAL=
    [[ -n "${COMP_LINE:-}" ]] || return 1
    local -r line_prefix=${COMP_LINE:0:${COMP_POINT:-${#COMP_LINE}}}

    local -i last_pipe=-1
    local -i seg_op=-1
    local -i seg_op_at_pipe=-1
    local in_squote=false
    local in_dquote=false
    local -i ci
    local ch
    for (( ci = 0; ci < ${#line_prefix}; ci++ ))
    do
        ch=${line_prefix:ci:1}
        if "$in_squote"
        then
            [[ "$ch" == "'" ]] && in_squote=false
            continue
        fi
        if "$in_dquote"
        then
            case "$ch" in
            '"') in_dquote=false ;;
            '\\') ((ci++)) ;;
            esac
            continue
        fi
        case "$ch" in
        "'") in_squote=true ;;
        '"') in_dquote=true ;;
        '\\') ((ci++)) ;;
        '|')
            if [[ "${line_prefix:ci+1:1}" == '|' ]]
            then
                # '||' is a segment separator, not a pipe. Point at the
                # second char so the producer starts after both.
                seg_op=$((ci + 1))
                ((ci++))
            else
                last_pipe=$ci
                seg_op_at_pipe=$seg_op
            fi
            ;;
        ';')
            seg_op=$ci
            ;;
        '&')
            # Both '&' (background) and '&&' separate segments
            seg_op=$ci
            if [[ "${line_prefix:ci+1:1}" == '&' ]]
            then
                seg_op=$((ci + 1))
                ((ci++))
            fi
            ;;
        esac
    done
    (( last_pipe >= 0 )) || return 1

    local producer_str=${line_prefix:seg_op_at_pipe+1:last_pipe-seg_op_at_pipe-1}
    # Trim leading/trailing whitespace
    producer_str=${producer_str#"${producer_str%%[![:space:]]*}"}
    producer_str=${producer_str%"${producer_str##*[![:space:]]}"}
    [[ -n "$producer_str" ]] || return 1

    BU_RET=$producer_str
    BU_RET_EVAL=$producer_str
}

__bu_out_resolve_producer()
{
    BU_RET=
    BU_RET_EVAL=

    # Resolve the producer pipeline text, most accurate source first:
    # - command_line_front_before_pipe: set by the fzf binding (legacy parser)
    # - pipe_before: set by the tree-sitter binding (BU_TS_RESULT[pipeBefore])
    # Both are locals of the completion bindings, visible via dynamic scope.
    local producer_str=${command_line_front_before_pipe:-${pipe_before:-}}
    if [[ -n "$producer_str" ]]
    then
        # Strip trailing whitespace, the pipe character, then whitespace again
        producer_str=${producer_str%"${producer_str##*[![:space:]]}"}
        producer_str=${producer_str%|}
        producer_str=${producer_str%"${producer_str##*[![:space:]]}"}
        BU_RET_EVAL=$producer_str
    elif __bu_out_resolve_producer_from_comp_line
    then
        # The completion driver exposes the raw command line: recover the
        # producer from the last unquoted pipe before the cursor. This path
        # needs neither COMP_WORDS nor COMP_CWORD.
        producer_str=$BU_RET
    else
        # Fallback: walk COMP_WORDS (dynamically scoped from the completion
        # driver) for the pipe that starts the current command segment.
        # Note plain bash completion (fzf binding disabled) hands the
        # completion function only the segment after the last pipe, so this
        # walk can only succeed for drivers that pass full-line COMP_WORDS.
        [[ -z "$COMP_CWORD" ]] && return 1
        local i pipe_idx=
        for (( i = COMP_CWORD - 1; i >= 0; i-- ))
        do
            if [[ "${COMP_WORDS[i]}" == '|' ]]
            then
                pipe_idx=$i
                break
            fi
        done
        # Not in a pipeline: no producer to infer values from
        [[ -z "$pipe_idx" ]] && return 1

        # The producer segment starts after the previous control operator
        local seg_start=0
        for (( i = pipe_idx - 1; i >= 0; i-- ))
        do
            case "${COMP_WORDS[i]}" in
            '|'|';'|'&&'|'||'|'('|')')
                seg_start=$((i + 1))
                break
                ;;
            esac
        done
        local -a producer_words=("${COMP_WORDS[@]:seg_start:pipe_idx-seg_start}")
        ((${#producer_words[@]} == 0)) && return 1
        producer_str="${producer_words[*]}"
        printf -v BU_RET_EVAL '%q ' "${producer_words[@]}"
    fi
    [[ -z "$producer_str" ]] && return 1

    # Canonicalize for registry key matching ("xx get-command" → "bu get-command")
    __bu_out_canonicalize_stage "$producer_str"
    BU_RET=$BU_CANONICAL_STAGE
}

__bu_out_complete_pipeline_fields()
{
    local is_dot=false
    local is_nested=false
    while (($#))
    do
        case "$1" in
        --dot) is_dot=true ;;
        --nested) is_nested=true ;;
        *) break ;;
        esac
        shift
    done
    local -r cur_word=${1:-}
    BU_RET=()

    # Resolve the producer pipeline text (and eval-able command) via the
    # shared resolver.
    __bu_out_resolve_producer || return 1
    local producer_str=$BU_RET
    local producer_eval=$BU_RET_EVAL
    BU_RET=()

    local -r producer_head=${producer_str%%[[:space:]]*}

    local -a fields=()

    # 1. Multi-stage pipeline static analysis: walk all stages, track field
    #    propagation through transforms (query-object, select/where aliases, etc.)
    if __bu_out_analyze_pipeline "$producer_str" fields && ((${#fields[@]} > 0))
    then
        : # fields populated by the analyzer
    else
    # 2. Static registry fallback: longest matching producer prefix wins.
    #    This handles pipelines where static analysis bailed (unknown commands)
    #    or where no multi-stage transforms exist.
    local key best_key=
    for key in "${!BU_OUT_PRODUCER_FIELDS[@]}"
    do
        if [[ "$producer_str" == "$key" || "$producer_str" == "$key "* ]] && (( ${#key} > ${#best_key} ))
        then
            best_key=$key
        fi
    done
    if [[ -n "$best_key" ]]
    then
        # shellcheck disable=SC2206 # Intentional word splitting of the field list
        fields=(${BU_OUT_PRODUCER_FIELDS[$best_key]})
    fi

    # 2b. Lazy # Fields: annotation — scan the producer script for a header
    # comment declaring its output schema, same pattern as # Synopsis:.
    if ((${#fields[@]} == 0))
    then
        # Extract command name from canonicalized producer ("bu get-module" → "get-module")
        local _ff_cmd_name=${producer_str#* }
        _ff_cmd_name=${_ff_cmd_name%%[[:space:]]*}
        if [[ -f "${BU_COMMANDS[$_ff_cmd_name]:-}" ]]
        then
            local _ff_line=
            __bu_command_header_get "${BU_COMMANDS[$_ff_cmd_name]}" "Fields" _ff_line
            if [[ -n "$_ff_line" ]]
            then
                # shellcheck disable=SC2206 # Intentional word splitting of the field list
                fields=($_ff_line)
                # Cache into the static registry so subsequent completions skip the parse
                BU_OUT_PRODUCER_FIELDS[$producer_str]=$_ff_line
            fi
        fi
    fi

    if ((${#fields[@]} == 0)) && "$BU_OUT_PROBE_PIPELINE" && [[ -n "${BU_OUT_PROBE_COMMANDS[$producer_head]:-}" && -n "$BU_OUT_JQ" ]]
    then
        # 3. Opt-in probing: execute the producer as typed, read the keys of
        # the first record. Auto-dispatch makes piped bu commands emit JSONL.
        local first_line
        first_line=$(eval "$producer_eval" 2>/dev/null | head -1)
        if [[ -n "$first_line" ]]
        then
            local keys
            keys=$("$BU_OUT_JQ" -r 'if type == "object" then keys_unsorted[] else empty end' <<<"$first_line" 2>/dev/null)
            [[ -n "$keys" ]] && mapfile -t fields <<<"$keys"
        fi
    fi

    # 4. Tab-Execute-Field gate: producer declared safe to execute for field
    #    discovery on a bare post-pipe TAB. No master switch — the
    #    per-producer declaration is the whole gate. The first captured
    #    record's keys become the field candidates.
    if ((${#fields[@]} == 0)) && [[ -n "$BU_OUT_JQ" ]]
    then
        local _tf_captured=
        if __bu_out_tab_execute_capture --field "$producer_str" "$producer_eval"
        then
            _tf_captured=$BU_RET
        fi
        BU_RET=()
        if [[ -n "$_tf_captured" ]]
        then
            local _tf_first_line=
            _tf_first_line=${_tf_captured%%$'\n'*}
            if [[ -n "$_tf_first_line" ]]
            then
                local _tf_keys=
                _tf_keys=$("$BU_OUT_JQ" -r 'if type == "object" then keys_unsorted[] else empty end' <<<"$_tf_first_line" 2>/dev/null)
                [[ -n "$_tf_keys" ]] && mapfile -t fields <<<"$_tf_keys"
            fi
        fi
    fi
    fi
    ((${#fields[@]} == 0)) && return 1

    # --- nested probing: walk all scalar paths from the first record ---
    local -a nested_paths=()
    if "$is_nested" && [[ -n "$BU_OUT_JQ" && -n "$producer_eval" ]]
    then
        local _np_first_line
        _np_first_line=$(eval "$producer_eval" 2>/dev/null | head -1)
        if [[ -n "$_np_first_line" ]]
        then
            local _np_raw
            _np_raw=$("$BU_OUT_JQ" -r 'paths(scalars) | map(tostring) | join(".")' <<<"$_np_first_line" 2>/dev/null)
            [[ -n "$_np_raw" ]] && mapfile -t nested_paths <<<"$_np_raw"

            # Include top-level object keys (paths with no dot) in fields
            # so the registry-only top-level list is augmented by any keys
            # only present in the actual data.
            local _np_path
            for _np_path in "${nested_paths[@]}"
            do
                if [[ "$_np_path" != *.* ]]
                then
                    local _np_seen=false
                    local _np_f
                    for _np_f in "${fields[@]}"
                    do
                        [[ "$_np_f" == "$_np_path" ]] && { _np_seen=true; break; }
                    done
                    "$_np_seen" || fields+=("$_np_path")
                fi
            done
        fi
    fi

    # Comma-aware emission: completing "name,ve" suggests "name,version" etc.,
    # excluding fields already present before the last comma
    local prefix=
    local -A used=()
    if [[ "$cur_word" == *,* ]]
    then
        prefix=${cur_word%,*},
        local used_field
        local ifs=$IFS
        IFS=','
        for used_field in ${cur_word%,*}
        do
            used[$used_field]=1
        done
        IFS=$ifs
    fi

    # Active segment is everything after the last comma
    local active_seg=${cur_word##*,}

    if "$is_nested" && [[ "$active_seg" == *.* ]]
    then
        # --- Tree-drill mode: completing "server.ho" → "server.host" ---
        # Split into parent path (everything before last dot) and leaf prefix
        local dot_parent=${active_seg%.*}.
        local dot_leaf_prefix=${active_seg##*.}

        local _np_path
        for _np_path in "${nested_paths[@]}"
        do
            # Must start with parent prefix (e.g. "server.")
            [[ "$_np_path" == "$dot_parent"* ]] || continue
            # Must be a direct child: no further dots after parent
            local _np_suffix=${_np_path#"$dot_parent"}
            [[ "$_np_suffix" == *.* ]] && continue
            # Must match leaf prefix
            [[ "$_np_suffix" == "$dot_leaf_prefix"* ]] || continue
            # Must not be already selected
            [[ -n "${used[$dot_parent$_np_suffix]:-}" ]] && continue

            local _np_candidate=${dot_parent}$_np_suffix
            "$is_dot" && _np_candidate=.$_np_candidate
            BU_RET+=("${prefix}${_np_candidate}")
        done
    else
        # --- Flat mode: complete top-level field names (with dot prefix if --dot) ---
        local field candidate
        for field in "${fields[@]}"
        do
            [[ -n "${used[$field]:-}" ]] && continue
            [[ "$field" == "$active_seg"* ]] || continue
            candidate=$field
            "$is_dot" && candidate=.$field
            BU_RET+=("${prefix}${candidate}")
        done
    fi
}

# ```
# *Description*:
# Capture the first N records from a tab-execute registered producer,
# memoized per producer string and shared across the field-name and
# field-value gates (one execution serves both positions on a pipeline).
#
# *Params*:
# - `--field` (optional): select the BU_OUT_TAB_EXECUTE_FIELD /
#   `# Tab-Execute-Field: true` gate; default is the value gate
#   (BU_OUT_TAB_EXECUTE / `# Tab-Execute: true`).
# - `$1`: Canonicalized producer string (e.g. "bu get-command")
# - `$2`: Eval-able producer command (from __bu_out_resolve_producer)
#
# *Returns*:
# - BU_RET: Captured rows (newline-separated JSONL), empty on failure
# - exit 0 on success, 1 if the producer isn't registered for the selected
#   gate, has no eval-able command, or produced no rows
# ```
__bu_out_tab_execute_capture()
{
    local is_field_gate=false
    if [[ "$1" == --field ]]
    then
        is_field_gate=true
        shift
    fi
    local -r producer_str=$1
    local -r producer_eval=$2
    BU_RET=

    # Longest-prefix match against the selected gate's registry, same lookup
    # as BU_OUT_PRODUCER_FIELDS so flags in the typed pipeline don't defeat it.
    local -n _gate_registry
    if "$is_field_gate"
    then
        _gate_registry=BU_OUT_TAB_EXECUTE_FIELD
    else
        _gate_registry=BU_OUT_TAB_EXECUTE
    fi
    local key best_key=
    for key in "${!_gate_registry[@]}"
    do
        if [[ "$producer_str" == "$key" || "$producer_str" == "$key "* ]] && (( ${#key} > ${#best_key} ))
        then
            best_key=$key
        fi
    done

    # Lazy header annotation scan-and-cache, so command authors declare the
    # opt-in next to their schema without central edits.
    if [[ -z "$best_key" ]]
    then
        local _te_cmd_name=${producer_str#* }
        _te_cmd_name=${_te_cmd_name%%[[:space:]]*}
        if [[ -f "${BU_COMMANDS[$_te_cmd_name]:-}" ]]
        then
            local _te_val=
            local _te_key
            if "$is_field_gate"
            then
                _te_key=Tab-Execute-Field
            else
                _te_key=Tab-Execute
            fi
            __bu_command_header_get "${BU_COMMANDS[$_te_cmd_name]}" "$_te_key" _te_val
            if [[ "$_te_val" == true ]]
            then
                _gate_registry[$producer_str]=1
                best_key=$producer_str
            fi
        fi
    fi

    [[ -z "$best_key" ]] && return 1
    [[ -z "$producer_eval" ]] && return 1

    # Capture rows once per producer_str per session, capped. BU_COMP_FAKE
    # prevents the producer (a bu command) from entering autocomplete mode
    # when COMP_CWORD is set in the completion context.
    if [[ -z "${__BU_OUT_TAB_ROWS[$producer_str]:-}" ]]
    then
        __BU_OUT_TAB_ROWS[$producer_str]=$(BU_COMP_FAKE=1 eval "$producer_eval" 2>/dev/null | head -"$__BU_OUT_VALUE_RECORD_CAP")
    fi
    BU_RET=${__BU_OUT_TAB_ROWS[$producer_str]}
    [[ -z "$BU_RET" ]] && return 1
    return 0
}

# ```
# *Description*:
# Complete distinct field VALUES from the live upstream pipeline at the
# where/query value position. Gated per producer: the resolved producer must
# be registered in BU_OUT_TAB_EXECUTE (a declaration that it is read-only
# and fast). Rows are captured once per producer_str per session, bounded by
# __BU_OUT_VALUE_RECORD_CAP, and reused across fields.
#
# *Params*:
# - `$1`: Field name whose values to extract
# - `$2` (optional): Current word (the caller applies prefix filtering)
#
# *Returns*:
# - BU_RET: Array of distinct value candidates
# - exit 0 on success, 1 if the producer isn't tab-execute registered or no
#   values could be captured
# ```
__bu_out_complete_field_values()
{
    local -r field=$1
    local -r cur_word=${2:-}
    BU_RET=()

    __bu_out_resolve_producer || return 1
    local producer_str=$BU_RET
    local producer_eval=$BU_RET_EVAL
    BU_RET=()

    [[ -z "$BU_OUT_JQ" ]] && return 1
    __bu_out_tab_execute_capture "$producer_str" "$producer_eval" || return 1
    local memo=$BU_RET
    BU_RET=()

    # Distinct scalar values for the field, capped. Skip values containing
    # newlines (they can't survive the enum round-trip line-oriented).
    local values
    values=$("$BU_OUT_JQ" -r --arg f "$field" '.[$f] | select(type == "string" or type == "number") | tostring | select(index("\n") == null)' <<<"$memo" 2>/dev/null \
        | sort -u | head -"$__BU_OUT_VALUE_DISTINCT_CAP")
    [[ -z "$values" ]] && return 1

    local v
    while IFS= read -r v
    do
        [[ -z "$v" ]] && continue
        BU_RET+=("$v")
    done <<<"$values"
    ((${#BU_RET[@]} == 0)) && return 1
    return 0
}

# MARK: Multi-stage pipeline static analysis

# Maps command names to how they transform record fields in a pipeline.
# Populated lazily from each command script's `# Pipeline:` header (no
# hand-maintained list); `bu_register_stage_effect` writes explicit entries
# for function/alias commands that have no file. Values:
#   producer           - emits initial fields (looked up in BU_OUT_PRODUCER_FIELDS)
#   passthrough        - output fields = input fields (distinct, foreach, measure)
#   project            - output fields = parsed from positional field-spec (compare-object)
#   query              - output fields from the --debug plan (query-object, where/select/grep/sort)
#   recordify_tsv      - output fields = parsed from --columns (convert-from-tsv)
#   recordify_lines    - output field = parsed from --column (convert-from-lines)
#   recordify_new      - output fields = keys from key=value pairs (new-record)
#   recordify_jc       - output fields = jc parser field map (convert-from-jc)
#   sink               - jsonl -> display (format-table, format-list, out-default)
#   codec              - format conversion (convert-to-X / convert-from-X)
declare -A -g BU_OUT_STAGE_EFFECT=()

# Effect -> "input:output" format tokens. `codec` is derived from the noun.
declare -A -g BU_OUT_EFFECT_IO=(
    [producer]="none:jsonl"
    [passthrough]="jsonl:jsonl"
    [project]="jsonl:jsonl"
    [query]="jsonl:jsonl"
    [sink]="jsonl:display"
    [consume]="jsonl:none"
    [recordify_tsv]="tsv:jsonl"
    [recordify_lines]="text:jsonl"
    [recordify_new]="none:jsonl"
    [recordify_jc]="text:jsonl"
)

# ```
# *Description*:
# Derive the (input, output) format tokens for a pipeline effect.  For a
# `codec` the non-jsonl format comes from the command noun (e.g.
# convert-to-json -> jsonl:json; convert-from-base64 -> base64:text).
#
# *Params*:
# - `$1`: Effect (see BU_OUT_STAGE_EFFECT values)
# - `$2`: Command name without the `bu ` prefix (e.g. "convert-to-json")
# - `$3`: Name of the variable to receive the input format (nameref)
# - `$4`: Name of the variable to receive the output format (nameref)
#
# *Returns*:
# - Always exits 0 (unknown effect yields empty tokens)
# ```
__bu_out_effect_io()
{
    local -r effect=$1
    local -r command_name=$2
    local -n _eff_in=$3
    local -n _eff_out=$4
    _eff_in=
    _eff_out=

    case "$effect" in
    codec)
        case "$command_name" in
        convert-to-base64)
            _eff_in=text
            _eff_out=base64
            ;;
        convert-from-base64)
            _eff_in=base64
            _eff_out=text
            ;;
        convert-to-*)
            _eff_in=jsonl
            _eff_out=${command_name#convert-to-}
            ;;
        convert-from-*)
            _eff_in=${command_name#convert-from-}
            _eff_out=jsonl
            ;;
        esac
        ;;
    *)
        local io=${BU_OUT_EFFECT_IO[$effect]:-}
        if [[ -n "$io" ]]
        then
            _eff_in=${io%%:*}
            _eff_out=${io#*:}
        fi
        ;;
    esac
    return 0
}

# ```
# *Description*:
# Resolve a command's pipeline stage effect.  Consulted in this order:
# 1. The in-memory cache BU_OUT_STAGE_EFFECT (populated by
#    bu_register_stage_effect and by previous header lookups).
# 2. The command script's `# Pipeline:` header, cached back into the registry
#    so the header is read at most once per file.
#
# *Params*:
# - `$1`: Command name without the `bu ` prefix (e.g. "convert-to-json")
# - `$2`: Name of the variable to receive the effect (nameref)
#
# *Returns*:
# - Sets the named variable to the effect (empty if unknown); always exits 0
# ```
__bu_out_stage_effect_lookup()
{
    local -r command_name=$1
    local -n _sel_out=$2
    _sel_out=
    local key="bu $command_name"

    if [[ -v BU_OUT_STAGE_EFFECT[$key] ]]
    then
        _sel_out=${BU_OUT_STAGE_EFFECT[$key]}
        return 0
    fi

    local file=${BU_COMMANDS[$command_name]:-}
    if [[ -f "$file" ]]
    then
        local _effect_val=
        __bu_command_header_get "$file" "Pipeline" _effect_val
        if [[ -n "$_effect_val" ]]
        then
            BU_OUT_STAGE_EFFECT[$key]=$_effect_val
            _sel_out=$_effect_val
        fi
    fi
    return 0
}

# ```
# *Description*:
# Register a command's pipeline stage effect for static field analysis.
#
# *Params*:
# - `$1`: Command name (e.g. `bu get-command`, `bu query-object`)
# - `$2`: Effect type: producer, passthrough, project, query, sink, codec,
#         recordify_tsv, recordify_lines, recordify_new, recordify_jc
#
# *Examples*:
# ```bash
# bu_register_stage_effect "bu get-command" producer
# bu_register_stage_effect "bu where" query
# bu_register_stage_effect "bu select" query
# ```
# ```
bu_register_stage_effect()
{
    local -r cmd=$1
    local -r effect=$2
    if [[ -z "$cmd" || -z "$effect" ]]
    then
        bu_log_err "Usage: bu_register_stage_effect <command> <effect>"
        return 1
    fi
    BU_OUT_STAGE_EFFECT[$cmd]=$effect
}

# ```
# *Description*:
# Report whether a pipeline command consuming `input` format can follow an
# upstream stage emitting `output` format.  Unknown formats are treated as
# compatible (do not filter), so only positively-known mismatches are hidden.
#
# *Params*:
# - `$1`: input format token (e.g. `jsonl`, `tsv`, `text`, `none`)
# - `$2`: output format token
#
# *Returns*:
# - exit 0 if compatible, 1 if known-incompatible
# ```
__bu_out_format_compatible()
{
    local -r input=$1
    local -r output=$2
    [[ -z "$input" || -z "$output" ]] && return 0
    [[ "$input" == "$output" ]] && return 0
    # A generic line-oriented "text" consumer accepts any line-oriented stream.
    [[ "$input" == text && "$output" != none && "$output" != display ]] && return 0
    return 1
}

# ```
# *Description*:
# Compute the output format of a producer pipeline (the stream that would
# reach the next stage after a pipe).  Walks each stage's effect and returns
# the final output format token.
#
# *Params*:
# - `$1`: Producer pipeline text (e.g. "bu get-command | bu convert-to-tsv")
# - `$2`: Name of the variable to receive the format token (nameref)
#
# *Returns*:
# - exit 0 and sets the token; exit 1 if any stage's effect/format is unknown
# ```
__bu_out_pipeline_output_format()
{
    local -r pipeline_text=$1
    local -n _pof_out=$2
    _pof_out=

    local -a _pof_stages=()
    __bu_out_split_pipeline "$pipeline_text" _pof_stages
    ((${#_pof_stages[@]} == 0)) && return 1

    local _pof_fmt=
    local _pof_stage _pof_cmd _pof_eff _pof_in _pof_o
    for _pof_stage in "${_pof_stages[@]}"
    do
        _pof_cmd=$(__bu_out_extract_command "$_pof_stage") || return 1
        _pof_eff=
        __bu_out_stage_effect_lookup "${_pof_cmd#bu }" _pof_eff
        [[ -z "$_pof_eff" ]] && return 1
        _pof_in= _pof_o=
        __bu_out_effect_io "$_pof_eff" "${_pof_cmd#bu }" _pof_in _pof_o
        [[ -z "$_pof_o" ]] && return 1
        _pof_fmt=$_pof_o
    done

    [[ -z "$_pof_fmt" ]] && return 1
    _pof_out=$_pof_fmt
    return 0
}

# ```
# *Description*:
# Read a command's fixed input-field contract (`# Requires-All:` header —
# every listed field must be present).
#
# *Params*:
# - `$1`: Command name without the `bu ` prefix
# - `$2`: Name of the variable to receive the space-joined fields (nameref)
# ```
__bu_out_command_requires_all()
{
    local -r command_name=$1
    local -n _cra_out=$2
    _cra_out=
    local _cra_file=${BU_COMMANDS[$command_name]:-}
    if [[ -f "$_cra_file" ]]
    then
        __bu_command_header_get "$_cra_file" "Requires-All" _cra_out
    fi
    return 0
}

# ```
# *Description*:
# Read a command's fallback input-field contract (`# Requires-Any:` header —
# at least one listed field must be present).
#
# *Params*:
# - `$1`: Command name without the `bu ` prefix
# - `$2`: Name of the variable to receive the space-joined fields (nameref)
# ```
__bu_out_command_requires_any()
{
    local -r command_name=$1
    local -n _crany_out=$2
    _crany_out=
    local _crany_file=${BU_COMMANDS[$command_name]:-}
    if [[ -f "$_crany_file" ]]
    then
        __bu_command_header_get "$_crany_file" "Requires-Any" _crany_out
    fi
    return 0
}

# ```
# *Description*:
# Report whether a field name is present in an array of field names.
#
# *Params*:
# - `$1`: Field name to look for
# - `$2`: Name of the array to search (nameref)
#
# *Returns*:
# - exit 0 if present, 1 if absent
# ```
__bu_out_field_present()
{
    local -r field=$1
    local -n _fp_arr=$2
    local _fp_f
    for _fp_f in "${_fp_arr[@]}"
    do
        [[ "$_fp_f" == "$field" ]] && return 0
    done
    return 1
}

# ```
# *Description*:
# Optional strict-mode stdin guard for pipeline consumers.  When
# BU_OUT_STRICT=true, reads the first JSONL record and warns to stderr if the
# command's `# Requires-All:` (all) / `# Requires-Any:` (at least one)
# contract is unsatisfied, then passes every record through unchanged.  When
# BU_OUT_STRICT is unset/false this is a plain `cat` (zero overhead).
#
# Meant to be wired into a consumer's stdin loop as
# `done < <(__bu_out_strict_guard "<command>")`, so the guard runs in a
# process substitution and the loop keeps reading the current shell.
#
# *Params*:
# - `$1`: Command name without the `bu ` prefix
# ```
__bu_out_strict_guard()
{
    local -r command_name=$1

    if [[ "${BU_OUT_STRICT:-false}" != true ]]
    then
        cat
        return 0
    fi

    # Peek the first record (preserving it verbatim), then pass everything through.
    local _sg_first
    IFS= read -r _sg_first || return 0

    local _sg_all= _sg_any=
    local _sg_file=${BU_COMMANDS[$command_name]:-}
    if [[ -f "$_sg_file" ]]
    then
        __bu_command_header_get "$_sg_file" "Requires-All" _sg_all
        __bu_command_header_get "$_sg_file" "Requires-Any" _sg_any
    fi

    if [[ -n "$BU_OUT_JQ" && ( -n "$_sg_all" || -n "$_sg_any" ) ]]
    then
        local -a _sg_missing=()
        if [[ -n "$_sg_all" ]]
        then
            local -a _sg_all_fields=()
            read -r -a _sg_all_fields <<< "$_sg_all"
            local _sg_r
            for _sg_r in "${_sg_all_fields[@]}"
            do
                if ! "$BU_OUT_JQ" -e --arg f "$_sg_r" 'has($f)' <<<"$_sg_first" >/dev/null 2>&1
                then
                    _sg_missing+=("$_sg_r")
                fi
            done
        fi
        if [[ -n "$_sg_any" ]]
        then
            local -a _sg_any_fields=()
            read -r -a _sg_any_fields <<< "$_sg_any"
            local _sg_r2 _sg_any_ok=false
            for _sg_r2 in "${_sg_any_fields[@]}"
            do
                if "$BU_OUT_JQ" -e --arg f "$_sg_r2" 'has($f)' <<<"$_sg_first" >/dev/null 2>&1
                then
                    _sg_any_ok=true
                    break
                fi
            done
            if ! "$_sg_any_ok"
            then
                local _sg_ifs=$IFS
                IFS='|'
                _sg_missing+=("${_sg_any_fields[*]}")
                IFS=$_sg_ifs
            fi
        fi
        if ((${#_sg_missing[@]} > 0))
        then
            bu_log_warn "BU_OUT_STRICT: [$command_name] needs field(s) [${_sg_missing[*]}] not present in upstream record"
        fi
    fi

    printf '%s\n' "$_sg_first"
    cat
    return 0
}

# ```
# *Description*:
# Statically resolve the record fields an upstream pipeline produces.  Uses
# multi-stage analysis, the static registry, and the `# Fields:` header — but
# never executes the producer (unlike completion probing / tab-execute).
#
# *Params*:
# - `$1`: Producer pipeline text
# - `$2`: Name of the array to receive the field names (nameref)
#
# *Returns*:
# - exit 0 if fields are known (array populated), 1 if unknown
# ```
__bu_out_static_pipeline_fields()
{
    local -r pipeline_text=$1
    local -n _spf_out=$2
    _spf_out=()

    local -a _spf_fields=()
    if __bu_out_analyze_pipeline "$pipeline_text" _spf_fields && ((${#_spf_fields[@]} > 0))
    then
        _spf_out=("${_spf_fields[@]}")
        return 0
    fi

    # Static registry longest-prefix match.
    local _spf_key _spf_best=
    for _spf_key in "${!BU_OUT_PRODUCER_FIELDS[@]}"
    do
        if [[ "$pipeline_text" == "$_spf_key" || "$pipeline_text" == "$_spf_key "* ]] && (( ${#_spf_key} > ${#_spf_best} ))
        then
            _spf_best=$_spf_key
        fi
    done
    if [[ -n "$_spf_best" ]]
    then
        # shellcheck disable=SC2206
        _spf_fields=(${BU_OUT_PRODUCER_FIELDS[$_spf_best]})
    fi

    # `# Fields:` header.
    if ((${#_spf_fields[@]} == 0))
    then
        local _spf_cmd=${pipeline_text#* }
        _spf_cmd=${_spf_cmd%%[[:space:]]*}
        local _spf_file=${BU_COMMANDS[$_spf_cmd]:-}
        if [[ -f "$_spf_file" ]]
        then
            local _spf_line=
            __bu_command_header_get "$_spf_file" "Fields" _spf_line
            [[ -n "$_spf_line" ]] && _spf_fields=($_spf_line)
        fi
    fi

    ((${#_spf_fields[@]} > 0)) || return 1
    _spf_out=("${_spf_fields[@]}")
    return 0
}

# ```
# *Description*:
# Filter a list of candidate command names for the command position after a
# pipe.  Hides commands whose input format is known-incompatible with the
# upstream stream, and — when the upstream fields are statically known —
# commands whose `# Requires:` fields are not all present upstream.  When no
# pipe context exists, or the upstream is unknown, the list is left unchanged.
#
# *Params*:
# - `$1`: Name of the candidate command array (nameref, filtered in place)
# ```
__bu_out_filter_compatible_commands()
{
    local -n _fcc_in=$1

    if ! __bu_out_resolve_producer
    then
        return 0
    fi
    local _fcc_producer=$BU_RET

    local _fcc_up_out=
    __bu_out_pipeline_output_format "$_fcc_producer" _fcc_up_out || return 0

    local -a _fcc_up_fields=()
    local _fcc_up_known=false
    if __bu_out_static_pipeline_fields "$_fcc_producer" _fcc_up_fields
    then
        _fcc_up_known=true
    fi

    local -a _fcc_result=()
    local _fcc_cmd
    for _fcc_cmd in "${_fcc_in[@]}"
    do
        local _fcc_eff= _fcc_in_fmt= _fcc_out_fmt=
        __bu_out_stage_effect_lookup "$_fcc_cmd" _fcc_eff
        if [[ -n "$_fcc_eff" ]]
        then
            __bu_out_effect_io "$_fcc_eff" "$_fcc_cmd" _fcc_in_fmt _fcc_out_fmt
            if [[ -n "$_fcc_in_fmt" ]] && ! __bu_out_format_compatible "$_fcc_in_fmt" "$_fcc_up_out"
            then
                continue
            fi
        fi

        if "$_fcc_up_known"
        then
            # Requires-All: every field must be present upstream.
            local _fcc_req_all=
            __bu_out_command_requires_all "$_fcc_cmd" _fcc_req_all
            if [[ -n "$_fcc_req_all" ]]
            then
                local -a _fcc_all_fields=()
                read -r -a _fcc_all_fields <<< "$_fcc_req_all"
                local _fcc_r _fcc_all_ok=true
                for _fcc_r in "${_fcc_all_fields[@]}"
                do
                    if ! __bu_out_field_present "$_fcc_r" _fcc_up_fields
                    then
                        _fcc_all_ok=false
                        break
                    fi
                done
                "$_fcc_all_ok" || continue
            fi
            # Requires-Any: at least one field must be present upstream.
            local _fcc_req_any=
            __bu_out_command_requires_any "$_fcc_cmd" _fcc_req_any
            if [[ -n "$_fcc_req_any" ]]
            then
                local -a _fcc_any_fields=()
                read -r -a _fcc_any_fields <<< "$_fcc_req_any"
                local _fcc_r2 _fcc_any_found=false
                for _fcc_r2 in "${_fcc_any_fields[@]}"
                do
                    if __bu_out_field_present "$_fcc_r2" _fcc_up_fields
                    then
                        _fcc_any_found=true
                        break
                    fi
                done
                "$_fcc_any_found" || continue
            fi
        fi

        _fcc_result+=("$_fcc_cmd")
    done

    _fcc_in=("${_fcc_result[@]}")
    return 0
}

# ```
# *Description*:
# Split a pipeline text (everything before the cursor's pipe) into individual
# stage texts. Uses `|` as the delimiter. The text comes from tree-sitter's
# pipeBefore, which is already CST-accurate — pipes inside strings or
# subshells are excluded.
#
# *Params*:
# - `$1`: Pipeline text (e.g. "bu get-command | bu select name")
# - nameref `$2`: Output array of trimmed stage texts
# ```
__bu_out_split_pipeline()
{
    local pipeline_text=$1
    local -n out_stages=$2
    out_stages=()

    [[ -z "$pipeline_text" ]] && return 0

    local -a raw=()
    local ifs=$IFS
    IFS='|'
    # shellcheck disable=SC2206 # Intentional word splitting on pipe
    raw=($pipeline_text)
    IFS=$ifs

    local stage
    for stage in "${raw[@]}"
    do
        # Trim leading/trailing whitespace
        stage=${stage#"${stage%%[![:space:]]*}"}
        stage=${stage%"${stage##*[![:space:]]}"}
        [[ -n "$stage" ]] && out_stages+=("$stage")
    done
}

# ```
# *Description*:
# Extract the command name from a pipeline stage text. Handles multi-word
# verbs (BU_MULTI_WORD_VERBS) so "bu convert-from-tsv --columns a,b" returns
# "bu convert-from-tsv".
#
# *Params*:
# - `$1`: Stage text
#
# *Returns*:
# - stdout: The resolved command name
# ```
# *Description*:
# Generate a pipeline context help string for use in bu_autohelp.
# Describes the command's role in a JSONL pipeline and, when pipeline
# context variables are available (during autocomplete), lists the
# upstream producer's fields.
#
# *Params*:
# - `$1`: Command name (e.g. "bu query-object")
# - `$2`: Indent string (e.g. "\t")
# - nameref `$3`: Output variable (receives the help text)
#
# *Returns*:
# - Sets the nameref variable to the pipeline help text, or empty
#   if the command has no known stage effect.
# ```
__bu_out_pipeline_help()
{
    local -r cmd_name=$1
    local -r indent=$2
    local -n _plh_out=$3
    _plh_out=

    # Canonicalize for registry key matching
    __bu_out_canonicalize_stage "$cmd_name"
    local canon=$BU_CANONICAL_STAGE

    local effect=
    __bu_out_stage_effect_lookup "${canon#bu }" effect
    [[ -z "$effect" ]] && return 0

    local role=
    case "$effect" in
    producer)
        role="Produces JSONL records from its own data sources."
        ;;
    passthrough)
        role="Reads JSONL records from stdin, applies a transformation, and emits JSONL to stdout."
        ;;
    project)
        role="Reads JSONL records from stdin, projects selected fields, and emits JSONL to stdout."
        ;;
    query)
        role="Reads JSONL records from stdin, applies SQL-style clauses (where, group-by, select, order-by, ...), and emits JSONL to stdout."
        ;;
    sink)
        role="Reads JSONL records from stdin and renders them for display on the terminal."
        ;;
    consume)
        role="Reads JSONL records from stdin and acts on each record (no structured output)."
        ;;
    codec)
        role="Converts between JSONL and another format (json, tsv, csv, base64, ...)."
        ;;
    recordify_tsv)
        role="Converts TSV from stdin to JSONL records."
        ;;
    recordify_lines)
        role="Converts line-oriented text from stdin to JSONL records."
        ;;
    recordify_new)
        role="Constructs a single JSONL record from key=value arguments. Standalone — does not read stdin."
        ;;
    recordify_jc)
        role="Converts structured text from stdin to JSONL records via jc parsers."
        ;;
    *)
        return 0
        ;;
    esac

    # Pipeline signature: <input> -> <output> format tokens.
    local _io_in= _io_out=
    __bu_out_effect_io "$effect" "${canon#bu }" _io_in _io_out
    local help_text="${indent}${role}"
    if [[ -n "$_io_in" && -n "$_io_out" ]]
    then
        help_text+=$'\n'"${indent}${_io_in} → ${_io_out}"
    fi

    # Input contracts (# Requires-All: / # Requires-Any:) when declared.
    local file=${BU_COMMANDS[${canon#bu }]:-}
    if [[ -f "$file" ]]
    then
        local _req_all=
        __bu_command_header_get "$file" "Requires-All" _req_all
        if [[ -n "$_req_all" ]]
        then
            help_text+=$'\n'"${indent}Requires fields: ${_req_all// /, }"
        fi
        local _req_any=
        __bu_command_header_get "$file" "Requires-Any" _req_any
        if [[ -n "$_req_any" ]]
        then
            help_text+=$'\n'"${indent}Requires one of: ${_req_any// /, }"
        fi
    fi

    # Check for pipeline context (available during autocomplete via dynamic scope)
    local producer_str=${command_line_front_before_pipe:-${pipe_before:-}}
    if [[ -n "$producer_str" ]]
    then
        producer_str=${producer_str%"${producer_str##*[![:space:]]}"}
        producer_str=${producer_str%|}
        producer_str=${producer_str%"${producer_str##*[![:space:]]}"}
        if [[ -n "$producer_str" ]]
        then
            # Resolve upstream fields (but don't pollute BU_RET for callers)
            local -a _plh_saved_ret=("${BU_RET[@]:-}")
            local -a _plh_fields=()
            if __bu_out_complete_pipeline_fields "" 2>/dev/null
            then
                _plh_fields=("${BU_RET[@]}")
            fi
            BU_RET=("${_plh_saved_ret[@]:-}")
            if ((${#_plh_fields[@]} > 0))
            then
                local _plh_joined="${_plh_fields[*]}"
                help_text+=$'\n'"${indent}Upstream fields: ${_plh_joined// /, }"
            fi
        fi
    fi

    _plh_out=$help_text
}

# ```
# *Description*:
# Canonicalize a pipeline stage text for registry key matching.
# Rewrites a leading "<cli> " prefix to "bu " — where <cli> is either
# BU_CLI_COMMAND_NAME (renamed CLIs) or a member of BU_CLI_COMMAND_ALIASES
# (additional completion names) — so that BU_OUT_PRODUCER_FIELDS and
# BU_OUT_STAGE_EFFECT lookups (keyed on "bu <cmd>") still match.
#
# *Params*:
# - `$1`: Stage text (e.g. "xx get-command --format json")
#
# *Returns*:
# - BU_CANONICAL_STAGE: Canonicalized stage text
# ```
__bu_out_canonicalize_stage()
{
    local stage=$1
    BU_CANONICAL_STAGE=$stage

    # Fast path: default CLI name and no completion aliases → nothing to rewrite.
    if [[ "$BU_CLI_COMMAND_NAME" == bu ]] && ((${#BU_CLI_COMMAND_ALIASES[@]} == 0))
    then
        return 0
    fi

    local -a _canon_words=()
    read -ra _canon_words <<< "$stage"
    ((${#_canon_words[@]} == 0)) && return 0

    local _first=${_canon_words[0]}
    local _is_cli_name=false
    if [[ "$_first" == "$BU_CLI_COMMAND_NAME" ]]
    then
        _is_cli_name=true
    else
        local _alias
        for _alias in "${BU_CLI_COMMAND_ALIASES[@]}"
        do
            if [[ "$_first" == "$_alias" ]]
            then
                _is_cli_name=true
                break
            fi
        done
    fi

    if "$_is_cli_name"
    then
        _canon_words[0]=bu
        BU_CANONICAL_STAGE="${_canon_words[*]}"
    fi
}

__bu_out_extract_command()
{
    local stage_text=$1
    [[ -z "$stage_text" ]] && return 1

    # Canonicalize the stage text so "xx get-command" → "bu get-command"
    __bu_out_canonicalize_stage "$stage_text"
    stage_text=$BU_CANONICAL_STAGE

    # Split into words
    local -a words=()
    # shellcheck disable=SC2206 # Intentional word splitting
    words=($stage_text)
    ((${#words[@]} == 0)) && return 1

    local cmd_name=${words[0]}

    # bu commands are always "bu <verb-noun>" (two words).
    # Multi-word verbs like "convert-from" make the noun start later,
    # but the command is still exactly two words.
    if [[ "$cmd_name" == bu ]] && ((${#words[@]} >= 2))
    then
        cmd_name="$cmd_name ${words[1]}"
    fi

    printf '%s' "$cmd_name"
}

# ```
# *Description*:
# Parse the output field names from a project-effect stage's field spec
# (e.g. compare-object). Handles "new=old" rename syntax — keeps the
# "new" (left-hand) names.
#
# *Params*:
# - `$1`: Stage text (e.g. "bu compare-object name,ver=version")
# - nameref `$2`: Output array of field names
# ```
__bu_out_parse_select_fields()
{
    local stage_text=$1
    local -n out_fields=$2
    out_fields=()

    # Canonicalize for registry key matching ("xx compare-object" → "bu compare-object")
    __bu_out_canonicalize_stage "$stage_text"
    stage_text=$BU_CANONICAL_STAGE

    local -a words=()
    # shellcheck disable=SC2206
    words=($stage_text)
    ((${#words[@]} < 2)) && return 1

    # Determine how many leading words form the command name.
    # bu commands are always two words (bu + verb-noun); others are one word.
    local cmd_word_count=1
    if [[ "${words[0]}" == bu ]] && ((${#words[@]} >= 2))
    then
        cmd_word_count=2
    fi

    # Find the first non-flag word after the command name — that's the field spec
    local i word field_spec=
    for (( i = cmd_word_count; i < ${#words[@]}; i++ ))
    do
        word=${words[i]}
        [[ "$word" == -* ]] && continue
        field_spec=$word
        break
    done

    [[ -z "$field_spec" ]] && return 1

    __bu_out_parse_field_spec "$field_spec" out_fields
    ((${#out_fields[@]} > 0)) && return 0
    return 1
}

# ```
# *Description*:
# Split a comma-separated field spec into output field names, keeping the
# left-hand name of "new=old" rename pairs. Shared by compare-object and
# query-object select-clause parsing.
#
# *Params*:
# - `$1`: Field spec (e.g. "name,ver=version")
# - nameref `$2`: Output array of field names
# ```
__bu_out_parse_field_spec()
{
    local field_spec=$1
    local -n _pfs_fields=$2
    _pfs_fields=()

    # Parse comma-separated specs: "new=old" → "new", "field" → "field"
    local spec new_name
    local ifs=$IFS
    IFS=','
    for spec in $field_spec
    do
        [[ -z "$spec" ]] && continue
        case "$spec" in
        *=*) new_name=${spec%%=*} ;;
        *)   new_name=$spec ;;
        esac
        _pfs_fields+=("$new_name")
    done
    IFS=$ifs
    ((${#_pfs_fields[@]} > 0)) && return 0
    return 1
}

# ```
# *Description*:
# Statically extract the output field names from a query-object stage that
# carries a select clause (e.g. "bu query-object select name,ver=version").
# Mirrors how the project effect parses a field spec, so the projected
# columns are known without running the stage.
#
# *Params*:
# - `$1`: Stage text (e.g. "bu query-object where verb -eq get select name")
# - nameref `$2`: Output array of field names
#
# *Returns*:
# - 0 if a select clause was found and parsed, 1 otherwise
# ```
__bu_out_parse_query_select_fields()
{
    local stage_text=$1
    local -n out_fields=$2
    out_fields=()

    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE

    local -a words=()
    # shellcheck disable=SC2206
    words=($canon)
    ((${#words[@]} < 3)) && return 1

    local i word prev field_spec
    for (( i = 1; i < ${#words[@]} - 1; i++ ))
    do
        word=${words[i]}
        case "$word" in
        select|--select)
            # Skip a bare "select" that is actually a comparison VALUE
            # (e.g. "where type -eq select") or a grep pattern ("grep select").
            prev=${words[i-1]}
            case "$prev" in
            -eq|-ne|-gt|-lt|-ge|-le|-like|-notlike|-match|-notmatch|-contains|-notcontains|-in|-notin|-ilike|-i|grep)
                continue
                ;;
            esac
            field_spec=${words[i+1]}
            [[ -z "$field_spec" || "$field_spec" == -* ]] && continue
            if __bu_out_parse_field_spec "$field_spec" out_fields
            then
                return 0
            fi
            ;;
        esac
    done
    return 1
}

# ```
# *Description*:
# Analyze a single pipeline stage: given its text and the input field names,
# compute the output field names after this stage executes.
#
# *Params*:
# - `$1`: Stage text
# - nameref `$2`: Input field names array
# - nameref `$3`: Output field names array (set by this function)
#
# *Returns*:
# - 0 on success, 1 if the stage effect is unknown and analysis should bail
# ```
__bu_out_analyze_stage()
{
    local stage_text=$1
    local -n _in_fields=$2
    local -n _out_fields=$3
    _out_fields=()

    # Canonicalize for registry key matching ("xx get-command" → "bu get-command")
    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE

    local cmd_name
    cmd_name=$(__bu_out_extract_command "$canon") || return 1

    # Resolve the effect from the command's `# Pipeline:` header (or the
    # in-memory registry cache).  cmd_name is "bu <verb-noun>"; strip the
    # "bu " prefix for the lookup.
    local effect=
    __bu_out_stage_effect_lookup "${cmd_name#bu }" effect
    if [[ -z "$effect" ]]
    then
        return 1
    fi

    case "$effect" in
    producer)
        # Look up static field registry
        local best_producer=
        for key in "${!BU_OUT_PRODUCER_FIELDS[@]}"
        do
            if [[ "$canon" == "$key" || "$canon" == "$key "* ]] && (( ${#key} > ${#best_producer} ))
            then
                best_producer=$key
            fi
        done
        if [[ -n "$best_producer" ]]
        then
            # shellcheck disable=SC2206
            _out_fields=(${BU_OUT_PRODUCER_FIELDS[$best_producer]})
        fi
        # Fall back to the producer's `# Fields:` header when the registry
        # has no entry (most producers declare their schema in-file).
        if ((${#_out_fields[@]} == 0))
        then
            local _prod_file=${BU_COMMANDS[${cmd_name#bu }]:-}
            if [[ -f "$_prod_file" ]]
            then
                local _prod_line=
                __bu_command_header_get "$_prod_file" "Fields" _prod_line
                [[ -n "$_prod_line" ]] && _out_fields=($_prod_line)
            fi
        fi
        ;;
    passthrough)
        _out_fields=("${_in_fields[@]}")
        ;;
    sink)
        # A sink renders records for display; field names pass through
        # unchanged (it terminates the JSONL stream anyway).
        _out_fields=("${_in_fields[@]}")
        ;;
    consume)
        # A consume command reads records and acts on them (no stream out);
        # field names pass through unchanged (it terminates the stream).
        _out_fields=("${_in_fields[@]}")
        ;;
    project)
        __bu_out_parse_select_fields "$canon" _out_fields || _out_fields=("${_in_fields[@]}")
        ;;
    query)
        # Statically parse a select clause first: when the query projects
        # fields (select a,b=version), the projected names are the output
        # fields, mirroring how the project effect parses a field spec.
        if __bu_out_parse_query_select_fields "$canon" _out_fields
        then
            : # projected fields populated statically
        elif [[ -n "$BU_OUT_JQ" ]]
        then
            # No static select clause: fall back to the query plan. --debug only
            # parses arguments (no stdin read, no jq expression execution).
            # BU_COMP_FAKE keeps a bu command from entering autocomplete mode
            # when COMP_CWORD is set in the completion context (same pattern as
            # __bu_out_tab_execute_capture). Uses eval on CST-vetted text (same
            # trust boundary as the existing probing system).
            local debug_out
            debug_out=$(BU_COMP_FAKE=1 eval "$stage_text --debug" 2>/dev/null) || true
            if [[ -n "$debug_out" ]]
            then
                local output_fields_json
                output_fields_json=$("$BU_OUT_JQ" -r '.outputFields // empty' <<<"$debug_out" 2>/dev/null) || true
                if [[ -n "$output_fields_json" && "$output_fields_json" != null ]]
                then
                    local parsed
                    parsed=$("$BU_OUT_JQ" -r '.[]' <<<"$output_fields_json" 2>/dev/null) || true
                    [[ -n "$parsed" ]] && mapfile -t _out_fields <<<"$parsed"
                fi
            fi
        fi
        # If we couldn't determine output fields (passthrough query), inherit input
        if ((${#_out_fields[@]} == 0))
        then
            _out_fields=("${_in_fields[@]}")
        fi
        ;;
    recordify_tsv)
        # Parse --columns from stage text
        local cols=
        if [[ "$stage_text" =~ --columns[[:space:]]+([^[:space:]]+) ]]
        then
            cols=${BASH_REMATCH[1]}
            cols=${cols%,}  # strip trailing comma if present
            local c new_name
            local ifs=$IFS
            IFS=','
            for c in $cols
            do
                [[ -z "$c" ]] && continue
                case "$c" in
                *:*) new_name=${c%%:*} ;;  # key:Label → key
                *)   new_name=$c ;;
                esac
                _out_fields+=("$new_name")
            done
            IFS=$ifs
        fi
        ;;
    recordify_lines)
        # Parse --column from stage text
        if [[ "$stage_text" =~ --column[[:space:]]+([^[:space:]]+) ]]
        then
            _out_fields=("${BASH_REMATCH[1]}")
        fi
        ;;
    recordify_new)
        # Parse key=value pairs: keys become output fields
        local -a rwords=()
        # shellcheck disable=SC2206
        rwords=($stage_text)
        local rword rkey
        for rword in "${rwords[@]}"
        do
            [[ "$rword" == -* ]] && continue
            [[ "$rword" == "${rwords[0]}" ]] && continue  # skip cmd name
            if [[ "$rword" == *=* && "$rword" != *:=* ]]
            then
                rkey=${rword%%=*}
                _out_fields+=("$rkey")
            elif [[ "$rword" == *:=* ]]
            then
                rkey=${rword%%:=*}
                _out_fields+=("$rkey")
            fi
        done
        ;;
    recordify_jc)
        # bu convert-from-jc: extract the parser name and look up the static
        # field map. Falls back to --discover if not found statically.
        local jc_parser=
        if [[ "$stage_text" =~ --parser[[:space:]]+([^[:space:]]+) ]]
        then
            jc_parser=${BASH_REMATCH[1]}
        fi
        if [[ -n "$jc_parser" ]]
        then
            # Look up in the static field map (registered with prefix matching)
            local jc_key="bu convert-from-jc --parser $jc_parser"
            local -a jc_fields=()
            # shellcheck disable=SC2206
            jc_fields=(${BU_OUT_PRODUCER_FIELDS[$jc_key]:-})
            if ((${#jc_fields[@]} > 0))
            then
                _out_fields=("${jc_fields[@]}")
            elif [[ -n "$BU_OUT_JQ" ]]
            then
                # Fall back to --discover (runs a sample invocation)
                local debug_out
                debug_out=$(eval "$stage_text --discover" 2>/dev/null) || true
                if [[ -n "$debug_out" ]]
                then
                    local output_fields_json
                    output_fields_json=$("$BU_OUT_JQ" -r '.outputFields // empty' <<<"$debug_out" 2>/dev/null) || true
                    if [[ -n "$output_fields_json" && "$output_fields_json" != null ]]
                    then
                        local parsed
                        parsed=$("$BU_OUT_JQ" -r '.[]' <<<"$output_fields_json" 2>/dev/null) || true
                        [[ -n "$parsed" ]] && mapfile -t _out_fields <<<"$parsed"
                    fi
                fi
            fi
        fi
        ;;
    *)
        # Unknown command — bail out, can't statically analyze
        return 1
        ;;
    esac

    return 0
}

# ```
# *Description*:
# Analyze a full pipeline (everything before the cursor's pipe) and compute
# the record fields available at the current stage. Walks each stage in
# order, tracking field propagation through transforms.
#
# *Params*:
# - `$1`: Pipeline text (pipe_before, with or without trailing pipe)
# - nameref `$2`: Output array of field names
#
# *Returns*:
# - 0 if analysis succeeded (fields populated), 1 if the pipeline contains
#   unknown/unsupported commands and static analysis must bail
#
# *Notes*:
# - The first stage must be a producer (has entry in BU_OUT_PRODUCER_FIELDS)
#   or the pipeline can't be statically analyzed.
# - If any stage returns unknown, the whole analysis bails.
# ```
__bu_out_analyze_pipeline()
{
    local pipeline_text=$1
    local -n _final_fields=$2
    _final_fields=()

    # Trim trailing pipe character and whitespace
    pipeline_text=${pipeline_text%"${pipeline_text##*[![:space:]]}"}
    pipeline_text=${pipeline_text%|}
    pipeline_text=${pipeline_text%"${pipeline_text##*[![:space:]]}"}

    [[ -z "$pipeline_text" ]] && return 1

    local -a stages=()
    __bu_out_split_pipeline "$pipeline_text" stages
    ((${#stages[@]} == 0)) && return 1

    local -a current_fields=()
    local -a next_fields=()
    local stage
    for stage in "${stages[@]}"
    do
        if ! __bu_out_analyze_stage "$stage" current_fields next_fields
        then
            return 1
        fi
        current_fields=("${next_fields[@]}")
    done

    ((${#current_fields[@]} == 0)) && return 1
    _final_fields=("${current_fields[@]}")
    return 0
}

# MARK: Backward field analysis (which fields a stage reads)

# ```
# *Description*:
# Split a comma-separated field spec into the INPUT field names a stage reads
# (the right-hand "old" name of "new=old" renames).
#
# *Params*:
# - `$1`: Field spec (e.g. "name,ver=version")
# - `$2`: Name of the array to receive the field names (nameref)
# ```
__bu_out_parse_field_spec_reads()
{
    local field_spec=$1
    local -n _pfr_out=$2
    _pfr_out=()

    local spec old_name
    local ifs=$IFS
    IFS=','
    # shellcheck disable=SC2206
    for spec in $field_spec
    do
        [[ -z "$spec" ]] && continue
        case "$spec" in
        *=*) old_name=${spec#*=} ;;
        *)   old_name=$spec ;;
        esac
        _pfr_out+=("$old_name")
    done
    IFS=$ifs
    return 0
}

# ```
# *Description*:
# Extract the input field names a select/project-style stage reads: the first
# non-flag positional after the command name, parsed as a field spec.
#
# *Params*:
# - `$1`: Stage text (e.g. "bu select name,ver=version")
# - `$2`: Name of the array to receive the field names (nameref)
# ```
__bu_out_parse_select_reads()
{
    local stage_text=$1
    local -n _psr_out=$2
    _psr_out=()

    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE
    local -a words=()
    read -r -a words <<< "$canon"
    ((${#words[@]} < 2)) && return 0

    local cmd_word_count=1
    [[ "${words[0]}" == bu ]] && cmd_word_count=2
    local i word spec=
    for (( i = cmd_word_count; i < ${#words[@]}; i++ ))
    do
        word=${words[i]}
        [[ "$word" == -* ]] && continue
        spec=$word
        break
    done
    [[ -z "$spec" ]] && return 0
    __bu_out_parse_field_spec_reads "$spec" _psr_out
    return 0
}

# ```
# *Description*:
# Extract the single field name a sort-style stage reads: the first non-flag
# positional after the command name.
#
# *Params*:
# - `$1`: Stage text (e.g. "bu sort name")
# - `$2`: Name of the array to receive the field name (nameref)
# ```
__bu_out_first_field_arg()
{
    local stage_text=$1
    local -n _ffa_out=$2
    _ffa_out=()

    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE
    local -a words=()
    read -r -a words <<< "$canon"
    ((${#words[@]} < 2)) && return 0

    local cmd_word_count=1
    [[ "${words[0]}" == bu ]] && cmd_word_count=2
    local i word
    for (( i = cmd_word_count; i < ${#words[@]}; i++ ))
    do
        word=${words[i]}
        [[ "$word" == -* ]] && continue
        _ffa_out=("$word")
        return 0
    done
    return 0
}

# ```
# *Description*:
# Extract the field names a structured `where` clause reads (the first field
# after each `where` keyword).  Raw-jq where expressions are skipped — they
# can't be statically parsed.
#
# *Params*:
# - `$1`: Stage text (e.g. "bu where type -eq source")
# - `$2`: Name of the array to receive the field names (nameref)
# ```
__bu_out_parse_where_reads()
{
    local stage_text=$1
    local -n _pwr_out=$2
    _pwr_out=()

    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE
    local -a words=()
    read -r -a words <<< "$canon"
    ((${#words[@]} < 3)) && return 0

    local i word fld
    for (( i = 1; i < ${#words[@]}; i++ ))
    do
        word=${words[i]}
        case "$word" in
        where|--where)
            fld=${words[i+1]:-}
            if [[ -n "$fld" && "$fld" != -* && "$fld" != .* && "$fld" != \(* ]]
            then
                _pwr_out+=("$fld")
            fi
            ;;
        esac
    done
    return 0
}

# ```
# *Description*:
# Extract the input field names a query-object stage reads from its clauses:
# select/group-by field specs (right-hand names) and structured where fields.
# order-by/having/grep are skipped (output-alias / post-group / any-field).
#
# *Params*:
# - `$1`: Stage text
# - `$2`: Name of the array to receive the field names (nameref)
# ```
__bu_out_parse_query_reads()
{
    local stage_text=$1
    local -n _pqr_out=$2
    _pqr_out=()

    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE
    local -a words=()
    read -r -a words <<< "$canon"
    ((${#words[@]} < 3)) && return 0

    local i word prev spec fld
    local -a _pqr_tmp=()
    for (( i = 1; i < ${#words[@]}; i++ ))
    do
        word=${words[i]}
        prev=${words[i-1]}
        case "$word" in
        select|--select|group-by|--group-by)
            # Skip a bare keyword that is actually a comparison value.
            case "$prev" in -eq|-ne|-gt|-lt|-ge|-le|-like|-notlike|-match|-notmatch|-contains|-notcontains|-in|-notin|-ilike|-i|grep) continue ;; esac
            spec=${words[i+1]:-}
            [[ -n "$spec" && "$spec" != -* ]] || continue
            _pqr_tmp=()
            __bu_out_parse_field_spec_reads "$spec" _pqr_tmp
            _pqr_out+=("${_pqr_tmp[@]}")
            ;;
        where|--where)
            fld=${words[i+1]:-}
            if [[ -n "$fld" && "$fld" != -* && "$fld" != .* && "$fld" != \(* ]]
            then
                _pqr_out+=("$fld")
            fi
            ;;
        esac
    done
    return 0
}

# ```
# *Description*:
# Determine which upstream fields a pipeline stage READS, from its effect and
# command name:
# - consume commands read their `# Requires:` fields
# - project (compare-object) reads the right-hand names of its field spec
# - query stages read sort/select/where/group-by field arguments
#
# *Params*:
# - `$1`: Stage text
# - `$2`: Name of the array to receive the field names (nameref)
# ```
__bu_out_stage_reads()
{
    local stage_text=$1
    local -n _sr_all=$2
    local -n _sr_any=$3
    _sr_all=()
    _sr_any=()

    __bu_out_canonicalize_stage "$stage_text"
    local canon=$BU_CANONICAL_STAGE
    local cmd_name
    cmd_name=$(__bu_out_extract_command "$canon") || return 0
    local plain=${cmd_name#bu }

    local effect=
    __bu_out_stage_effect_lookup "$plain" effect
    [[ -z "$effect" ]] && return 0

    case "$effect" in
    consume)
        local req_all=
        __bu_out_command_requires_all "$plain" req_all
        read -r -a _sr_all <<< "$req_all"
        local req_any=
        __bu_out_command_requires_any "$plain" req_any
        read -r -a _sr_any <<< "$req_any"
        ;;
    project)
        __bu_out_parse_select_reads "$canon" _sr_all
        ;;
    query)
        case "$plain" in
        sort)         __bu_out_first_field_arg "$canon" _sr_all ;;
        select)       __bu_out_parse_select_reads "$canon" _sr_all ;;
        where)        __bu_out_parse_where_reads "$canon" _sr_all ;;
        query-object) __bu_out_parse_query_reads "$canon" _sr_all ;;
        esac
        ;;
    esac
    return 0
}

# ```
# *Description*:
# Statically validate a pipeline's field references.  Walks each stage,
# tracking the fields available at each point, and collects the names of any
# field a stage reads that is not produced upstream.  Unknown stages make the
# available-field set unknown, which skips further validation (no false
# positives).
#
# *Params*:
# - `$1`: Pipeline text (e.g. "bu get-command | bu sort madeup")
#
# *Returns*:
# - BU_RET: array of missing field names (empty = pipeline is field-valid)
# - Always exits 0
# ```
__bu_out_validate_pipeline()
{
    local pipeline_text=$1
    BU_RET=()

    pipeline_text=${pipeline_text%"${pipeline_text##*[![:space:]]}"}
    pipeline_text=${pipeline_text%|}
    pipeline_text=${pipeline_text%"${pipeline_text##*[![:space:]]}"}
    [[ -z "$pipeline_text" ]] && return 0

    local -a stages=()
    __bu_out_split_pipeline "$pipeline_text" stages
    ((${#stages[@]} == 0)) && return 0

    local -a _vp_avail=()
    local known=false
    local stage
    local -a reads_all=()
    local -a reads_any=()
    local -a _vp_out=()
    for stage in "${stages[@]}"
    do
        __bu_out_stage_reads "$stage" reads_all reads_any
        if "$known"
        then
            # Requires-All reads: warn per missing field.
            local r
            for r in "${reads_all[@]}"
            do
                __bu_out_field_present "$r" _vp_avail || BU_RET+=("$r")
            done
            # Requires-Any reads: warn only when NONE are present.
            if ((${#reads_any[@]} > 0))
            then
                local r2 any_found=false
                for r2 in "${reads_any[@]}"
                do
                    if __bu_out_field_present "$r2" _vp_avail
                    then
                        any_found=true
                        break
                    fi
                done
                if ! "$any_found"
                then
                    local any_ifs=$IFS
                    IFS='|'
                    BU_RET+=("${reads_any[*]}")
                    IFS=$any_ifs
                fi
            fi
        fi

        if __bu_out_analyze_stage "$stage" _vp_avail _vp_out
        then
            _vp_avail=("${_vp_out[@]}")
            if ((${#_vp_avail[@]} > 0))
            then
                known=true
            else
                known=false
            fi
        else
            known=false
            _vp_avail=()
        fi
    done
    return 0
}

# MARK: Dispatcher (Out-Default)

# ```
# *Description*:
# Format a JSONL stream, auto-detecting the best format (PowerShell Out-Default).
#
# Format resolution order (first match wins):
# 1. Explicit `--format`
# 2. `$BU_OUTPUT_FORMAT` environment variable
# 3. stdout is a terminal -> `table`; otherwise (pipe/file) -> `jsonl`
#
# *Params*:
# - `--format auto|table|list|json|jsonl|tsv`: Output format (default: auto)
# - `--columns a,b,c`: Forwarded to table/list/tsv formatters
# - `--stream`: Forwarded to the table formatter
# - `--colors k=color,...`: Forwarded to the table formatter
# - `--style name`: Forwarded to the table formatter (see BU_TABLE_STYLE)
# - stdin: JSONL stream
#
# *Returns*:
# - stdout: Formatted output
#
# *Examples*:
# ```bash
# bu get-module --format jsonl | bu out --format table --columns name,version
# ```
bu_out()
{
    __bu_out_assert_jq || return 1

    local format=auto
    local columns=
    local colors=
    local style=
    local is_stream=false
    local shift_by=1
    while (($#))
    do
        shift_by=1
        case "$1" in
        --format)
            format=$2
            shift_by=2
            ;;
        --columns)
            columns=$2
            shift_by=2
            ;;
        --colors)
            colors=$2
            shift_by=2
            ;;
        --style)
            style=$2
            shift_by=2
            ;;
        --stream)
            is_stream=true
            ;;
        *)
            bu_log_err "Unrecognized option[$1] for bu_out"
            return 1
            ;;
        esac
        if (( $# < shift_by ))
        then
            bu_log_err "Expected $((shift_by - 1)) arguments for option $1"
            return 1
        fi
        shift "$shift_by"
    done

    if [[ "$format" == auto || -z "$format" ]]
    then
        if [[ -n "$BU_OUTPUT_FORMAT" ]]
        then
            format=$BU_OUTPUT_FORMAT
        elif [[ -t 1 ]]
        then
            format=table
        else
            format=jsonl
        fi
    fi

    # Auto-colour table columns on a terminal when no explicit --colors given
    if [[ -z "$colors" && "$format" == table && -t 1 ]]
    then
        colors=auto
    fi

    local -a formatter_args=()
    case "$format" in
    table)
        [[ -n "$columns" ]] && formatter_args+=(--columns "$columns")
        [[ -n "$colors" ]] && formatter_args+=(--colors "$colors")
        [[ -n "$style" ]] && formatter_args+=(--style "$style")
        "$is_stream" && formatter_args+=(--stream)
        bu_format_table "${formatter_args[@]}"
        ;;
    list)
        [[ -n "$columns" ]] && formatter_args+=(--columns "$columns")
        bu_format_list "${formatter_args[@]}"
        ;;
    tsv)
        [[ -n "$columns" ]] && formatter_args+=(--columns "$columns")
        bu_format_tsv "${formatter_args[@]}"
        ;;
    json)
        bu_format_json
        ;;
    jsonl)
        bu_format_jsonl
        ;;
    *)
        bu_log_err "Unrecognized format[$format]. Expected one of: auto, table, list, json, jsonl, tsv"
        return 1
        ;;
    esac
}
