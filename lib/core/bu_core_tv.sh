# bash-ide source=./bu_core_base.sh
# bash-ide source=./bu_core_out.sh

# MARK: Interactive table viewer (bu tv)
#
# A pure-Bash TUI table viewer for JSONL streams.  Provides fixed headers, a
# cell cursor, interactive sort, incremental search, a record-detail overlay
# and terminal resize handling — all with vim/less keybindings.
#
# Pipe any JSONL stream into it:
#     bu get-command | bu view-table
#     bu get-command | bu view-table --colors none
#     bu get-command | bu view-table --columns name,type --max-width 30
#
# Keys (table):
#     j k ↑ ↓            cursor row         h l ← →          cursor column
#     g G                first / last row   0 $ Home End     first / last column
#     Space b PgDn PgUp Shift-↓ Shift-↑     page rows (cursor and viewport)
#     Shift-→ Shift-← Ctrl-→ Ctrl-←         page columns
#     Ctrl-D Ctrl-U      half page down / up (cursor only)
#     s S                sort the cursor column (toggle / descending)
#     w W                widen the cursor column / all columns
#     f                  freeze (pin left) / unfreeze the cursor column
#     - + < >            hide the cursor column, bring hidden back, move it
#     / ? n N            search forward / backward, next / previous match
#     &                  filter rows (literal, smart case)
#     Esc                clear the search, then the filter
#     Enter              record detail      H F1             help
#     c                  column sidebar     Ctrl-L           re-measure terminal
#     m                  mouse reporting    q Q              quit
#
# Row actions (--action KEY[:LABEL]=COMMAND): KEY runs COMMAND in the
# viewer's own shell (eval) with the cursor record in BU_TV_RECORD; its last
# output line shows on the status line. Their hints lead the status line,
# undimmed and set off from the built-in keys by a "·"; the help lists them
# first, under "Actions", above the built-in keys. With --reload COMMAND the rows are
# then replaced by COMMAND's JSONL output, the cursor staying on its record
# (matched by the --key column). Actions can ask for input with bu_tv_prompt
# and run interactive programs with bu_tv_interactive.
# Preview (--preview COMMAND, inside tmux or zellij): p splits a pane off
# beside the viewer and shows COMMAND's output for the cursor record there,
# following the cursor. COMMAND runs in the background with the record in
# BU_TV_RECORD and COLUMNS/LINES set to the pane's size; the pane itself
# runs only a placeholder, its tty written by the viewer. Outside a
# multiplexer p only says so.
# The cursor row is reversed; its cursor cell is drawn un-reversed, bold
# and underlined.  Numeric columns are right-aligned and null shows as a
# dim ∅.  With the
# sidebar hidden, "◂ N" / "N ▸" on the separator row count the columns
# scrolled off each side.  NO_COLOR turns colours off by default.
#
# Keys (detail overlay): j k ↑ ↓ and the page keys scroll, g G top / bottom,
# J K next / previous record, n N next / previous match, q Q Esc Enter back.
#
# Mouse (SGR reporting, on while the TUI is up; m toggles it so the
# terminal can select text): click a cell to move the cursor, double-click
# a row for its detail, click a header or sidebar entry to select the
# column, wheel scrolls three rows (the sidebar list over a sidebar taller
# than the screen), the scrollbar right of the table (shown while the rows
# overflow) pages on a click and scrolls by its thumb.  The cursor
# column's sidebar entry has ⇤ (freeze / unfreeze) and × (hide) buttons;
# drag an entry to move its column, across the ╌ divider below the frozen
# columns to freeze or unfreeze it, or onto the Hidden list to hide it;
# click or drag a hidden entry out to bring it back.  Clicking a hint on
# the status line presses its key.  In an overlay the wheel scrolls and a
# click goes back (a hint presses its key).

# ── Terminal escape sequences (computed once at source time) ─────────────
declare -g -r __BU_TV_ESC=$'\e'
declare -g -r __BU_TV_ALT_SCREEN_ON="${__BU_TV_ESC}[?1049h"
declare -g -r __BU_TV_ALT_SCREEN_OFF="${__BU_TV_ESC}[?1049l"
declare -g -r __BU_TV_CURSOR_HOME="${__BU_TV_ESC}[H"
declare -g -r __BU_TV_CURSOR_HIDE="${__BU_TV_ESC}[?25l"
declare -g -r __BU_TV_CURSOR_SHOW="${__BU_TV_ESC}[?25h"
declare -g -r __BU_TV_CLEAR_SCREEN="${__BU_TV_ESC}[2J"
declare -g -r __BU_TV_CLEAR_LINE="${__BU_TV_ESC}[K"
declare -g -r __BU_TV_REVERSE="${__BU_TV_ESC}[7m"
declare -g -r __BU_TV_DIM="${__BU_TV_ESC}[2m"
# Neither bold nor dim: lifts the row-action hints out of the dimmed status
declare -g -r __BU_TV_NORMAL_INTENSITY="${__BU_TV_ESC}[22m"
# Raw CSI only — never tput-derived: sgr0 is \e(B\e[m under xterm, \e[m\017
# under screen and empty under dumb, so frames would depend on TERM.
declare -g -r __BU_TV_RESET="${__BU_TV_ESC}[0m"
declare -g -r __BU_TV_RESET_SHORT="${__BU_TV_ESC}[m"
declare -g -r __BU_TV_BOLD="${__BU_TV_ESC}[1m"
declare -g -r __BU_TV_BOLD_UNDERLINE="${__BU_TV_ESC}[1;4m"
# Search hit: black on yellow, or under NO_COLOR bold underlined reverse
# (it shows in plain rows, the reversed cursor row and the cursor cell)
declare -g -r __BU_TV_HIT="${__BU_TV_ESC}[43;30m"
declare -g -r __BU_TV_HIT_NO_COLOR="${__BU_TV_ESC}[1;4;7m"
# The cursor cell inside the reversed cursor row: un-reversed, bold and
# underlined across its width, like the cursor column's header
declare -g -r __BU_TV_CURSOR_CELL="${__BU_TV_ESC}[1;4m"
# Cell cache marker for null (a lone U+0002; a literal one is escaped)
declare -g -r __BU_TV_NULL=$'\x02'
declare -g -r __BU_TV_NULL_CELL="${__BU_TV_DIM}∅${__BU_TV_RESET}"
# Divider after the frozen columns, in place of their 2-column gap
declare -g -r __BU_TV_FROZEN_GAP="${__BU_TV_DIM}│${__BU_TV_ESC}[22m "
# Mouse reporting: presses (1000), motion while a button is held (1002), SGR
# encoding (1006); disabled in reverse order
declare -g -r __BU_TV_MOUSE_ON="${__BU_TV_ESC}[?1000h${__BU_TV_ESC}[?1002h${__BU_TV_ESC}[?1006h"
declare -g -r __BU_TV_MOUSE_OFF="${__BU_TV_ESC}[?1006l${__BU_TV_ESC}[?1002l${__BU_TV_ESC}[?1000l"
# SGR mouse report body (between "\e[<" and the final M/m): btn;x;y
declare -g -r __BU_TV_MOUSE_RE='^([0-9]{1,6});([0-9]{1,6});([0-9]{1,6})$'
# Scrollbar glyphs: a dim track and a solid thumb
declare -g -r __BU_TV_SB_TRACK="${__BU_TV_DIM}░${__BU_TV_RESET}"
declare -g -r __BU_TV_SB_THUMB='█'
# Two presses on the same row within this many ms open the detail overlay
declare -g -r -i __BU_TV_DOUBLE_CLICK_MS=400

# ── State ────────────────────────────────────────────────────────────────
declare -g -a _TV_ROWS=()           # Raw JSON strings, one per record
declare -g -a _TV_COLUMNS=()        # Column keys (e.g. name, version)
declare -g -a _TV_HEADERS=()        # Display labels (parsed from key:Label)
declare -g -A _TV_COLORS=()         # key → ANSI escape code (or empty)
declare -g -a _TV_CELLS=()          # Flat cell cache: [row * ncols + col] → string value
declare -g -a _TV_ROW_TEXT=()       # Per row: ANSI-stripped cells joined by U+0001 (search)
declare -g -i _TV_NUM_ROWS=0       # Data rows
declare -g -i _TV_NUM_COLS=0
declare -g -a _TV_VIEW=()           # Row view: view index → data row index (filtered)
declare -g -i _TV_NUM_VIEW=0        # Rows in the view; cursor and offsets are view indices
declare -g    _TV_FILTER_QUERY=     # Row filter (&): literal, smart case; empty = all rows
declare -g -a _TV_COL_CONTENT_W=()  # Widest cell per column (cache pass)
declare -g -a _TV_COL_NUMERIC=()    # Per column: 1 when every non-null value is a number
declare -g -a _TV_COL_FULL_WIDTHS=()  # Untruncated width per column (max of header, cells)
declare -g -a _TV_COL_EXPANDED=()   # Per column: "true" when widened with w/W
declare -g -a _TV_COL_WIDTHS=()     # Effective width per column (__bu_tv_compute_widths)
declare -g -i _TV_MAX_EFF_W=0       # Widest effective column
declare -g -i _TV_MAX_WIDTH=40      # Column width cap unless expanded (--max-width)
declare -g -i _TV_CUR_ROW=0         # Cursor row (0-indexed)
declare -g -i _TV_CUR_COL=0         # Cursor column (0-indexed)
declare -g -i _TV_ROW_OFFSET=0      # First visible row, derived from the cursor
declare -g -i _TV_COL_OFFSET=0      # First visible column, derived from the cursor
declare -g    _TV_SORT_COL=         # Column key for sort, empty = unsorted
declare -g    _TV_SORT_DIR=         # "asc" or "desc"
declare -g -a _TV_SORT_PERM=()      # Last sort: new row index → old row index
declare -g    _TV_SEARCH_QUERY=     # Current search string (literal, smart case)
declare -g    _TV_SEARCH_NEEDLE=    # Query as matched: lowercased unless case-sensitive
declare -g    _TV_SEARCH_FOLD=true  # false when the query has an uppercase character
declare -g -a _TV_MATCHED_ROWS=()   # Ascending indices of rows matching the query
declare -g -a _TV_MATCHED_COLS=()   # Parallel: first matching column of each row
declare -g -i _TV_MATCH_IDX=-1      # Match last moved to by __bu_tv_goto_match
declare -g -i _TV_FOUND_IDX=-1      # Out-param: __bu_tv_search_from
declare -g -a _TV_HITS=()           # Out-param: hit start offsets (__bu_tv_find_hits)
declare -g    _TV_PAINT=            # Out-param: highlighted text (__bu_tv_paint)
declare -g -a _TV_SEGS=()           # Out-param: (start len)... pairs (__bu_tv_wrap)
declare -g    _TV_STATUS=           # Out-param: status line (__bu_tv_compose_status)
declare -g    _TV_SEARCH_STATUS=    # Out-param: search part (__bu_tv_search_status)
declare -g -i _TV_TERM_ROWS=24
declare -g -i _TV_TERM_COLS=80
declare -g    _TV_SAVED_STTY=       # Saved stty settings for cleanup
declare -g -a _TV_VIS_COLS=()       # Visible column indices, computed once per frame
declare -g    _TV_SIDEBAR=true      # Show the column sidebar (toggled with c)
declare -g -i _TV_TABLE_COLS=80     # Screen columns left for the table (__bu_tv_update_layout)
declare -g -i _TV_SIDEBAR_W=0       # Sidebar width incl. border, 0 = hidden
declare -g -i _TV_SIDEBAR_NAME_W=0  # Column-name width inside the sidebar
declare -g    _TV_FC_TEXT=          # Out-param: formatted cell text (__bu_tv_format_cell)
declare -g -i _TV_FC_VIS_LEN=0      # Out-param: visible width of _TV_FC_TEXT (ANSI excluded)
declare -g    _TV_MODE=table        # table, detail or help
declare -g    _TV_HELP_RETURN=table # Mode the help overlay returns to
declare -g -a _TV_DETAIL_VALUES=()  # Detail overlay: untruncated value per column
declare -g -a _TV_DETAIL_LINES=()   # Detail overlay: rendered, wrapped lines
declare -g -a _TV_DETAIL_COL_LINE=()  # Detail overlay: first line index of each column
declare -g -i _TV_DETAIL_OFFSET=0   # Detail overlay: first visible line
declare -g -i _TV_HELP_OFFSET=0     # Help overlay: first visible line
declare -g    _TV_PROMPT_ACTIVE=false  # Search prompt open on the status row
declare -g    _TV_PROMPT_TEXT=      # Prompt shown while open ("/" or "?" + query)
declare -g -a _TV_ACTION_KEYS=()    # Row action keys, in the order given
declare -g -A _TV_ACTION_CMD=()     # Row action key -> command (eval'd in-process)
declare -g -A _TV_ACTION_LABEL=()   # Row action key -> hint label
declare -g    _TV_RELOAD_CMD=       # Command whose JSONL replaces the rows after an action
declare -g    _TV_KEY_COL=          # Column identifying a record across reloads
declare -g    _TV_MESSAGE=          # Status-line message from the last action
declare -g    _TV_ACTION_OUT=       # File capturing a running action's output
declare -g    _TV_PREVIEW_CMD=      # --preview: command previewing the cursor record
declare -g    _TV_PREVIEW_PANE=     # tmux pane id of the open preview pane
declare -g    _TV_PREVIEW_LAST=     # Record the preview pane last showed
declare -g    _TV_PREVIEW_STALE=false  # Redraw the preview even for the same record
declare -g -i _TV_PREVIEW_GEN=0     # Generation of the latest preview job
declare -g -i _TV_PREVIEW_PID=0     # Latest preview job (0: none)
declare -g    _TV_PREVIEW_GEN_FILE= # Latest generation, for the jobs to check
declare -g    _TV_PREVIEW_MUX=      # tmux, zellij or none (empty: not looked yet)
declare -g    _TV_PREVIEW_TTY_FILE= # The preview pane's tty and placeholder pid
declare -g    _TV_KEY=              # Out-param: last key read (__bu_tv_read_key)
declare -g    _TV_EOF=false         # The tty hit EOF (read_key reports it as "q")
declare -g    _TV_QUIT=false        # Event-loop exit flag
declare -g    _TV_HIT_ATTR=$__BU_TV_HIT  # Search hit attribute (__bu_tv_resolve_colors)
declare -g -i _TV_FROZEN_N=0        # Frozen columns: the prefix [0, N) stays pinned left (f)
declare -g -i _TV_FROZEN_EFF=0      # Frozen prefix in effect: 0 while it leaves no room to scroll
declare -g -i _TV_FROZEN_COST=0     # Screen columns the frozen prefix takes (widths + gaps)
declare -g -a _TV_HIDDEN=()         # Hidden columns (-), a stack: index US frozen US key US header US expanded
declare -g    _TV_MOUSE=true        # Mouse reporting on (toggled with m)
declare -g    _TV_MOUSE_EVENT=      # Out-param (key "mouse"): press release drag wheel_up wheel_down
declare -g -i _TV_MOUSE_BUTTON=0    # Out-param: 0 left, 1 middle, 2 right
declare -g -i _TV_MOUSE_X=0         # Out-param: 1-based screen column
declare -g -i _TV_MOUSE_Y=0         # Out-param: 1-based screen row
declare -g -i _TV_NOW_MS=0          # Out-param: __bu_tv_now_ms
declare -g -i _TV_CLICK_ROW=-1      # Row of the last left press (double-click), -1 = none
declare -g -i _TV_CLICK_MS=0        # Time of the last left press
declare -g -i _TV_SCROLLBAR_W=0     # 2 (gap + bar) while rows overflow, else 0
declare -g -i _TV_SB_TOP=0          # Out-param: thumb top in the track (__bu_tv_scrollbar_thumb)
declare -g -i _TV_SB_HEIGHT=0       # Out-param: thumb height
declare -g -i _TV_SB_ROOM=0         # Out-param: track rows the thumb top can move over
declare -g -i _TV_SB_MAX_OFF=0      # Out-param: largest row offset
declare -g    _TV_SB_GRABBED=false  # The thumb is being dragged
declare -g -i _TV_SB_GRAB_DY=0      # Pointer row minus thumb top when grabbed
declare -g -i _TV_SIDEBAR_START=0   # Sidebar list window [start, end) drawn last frame
declare -g -i _TV_SIDEBAR_END=0
declare -g -i _TV_SIDEBAR_NROWS=0   # Sidebar list length last frame
declare -g -a _TV_SIDEBAR_LIST_KIND=()  # Sidebar list rows: col div title hid (__bu_tv_sidebar_list)
declare -g -a _TV_SIDEBAR_LIST_ARG=()   # Parallel: column or hidden-stack index, else -1
declare -g -a _TV_SIDEBAR_ROW_IDX=()    # Per data row: list row drawn, -1/-2 more up/down, -3 blank
declare -g -i _TV_SIDEBAR_SCROLL=-1 # Sidebar list start set by the wheel, -1 = follow the viewport
declare -g    _TV_SIDEBAR_DRAG=     # Sidebar entry pressed for a drag: col or hid, empty = none
declare -g    _TV_SIDEBAR_DRAG_ID=  # Its column key, or hidden-stack index
declare -g -i _TV_SIDEBAR_DRAG_ROW=0    # Data row it was pressed on
declare -g -i _TV_SIDEBAR_DROP_ROW=-99  # Data row under the pointer once dragged (< 0: title rows), -99 = not moved
declare -g    _TV_FOUND_LABEL=      # Out-param: __bu_tv_hidden_label
declare -g    _TV_STATUS_HINTS=     # Hints on the status line last drawn (clickable)
declare -g -i _TV_STATUS_HINTS_X=0  # Their first screen column
# Signal flags: the traps only set these; __bu_tv_process_signals does the
# work from the event loop (see __bu_tv_install_traps for why)
declare -g    _TV_RESIZE_PENDING=false   # SIGWINCH
declare -g    _TV_SUSPEND_PENDING=false  # SIGTSTP (Ctrl-Z)
declare -g    _TV_RESUME_PENDING=false   # SIGCONT (fg)
# Blocking key reads wake this often (seconds) so a deferred WINCH trap runs
declare -g -r __BU_TV_KEY_POLL=0.1

# Table hints, dropped right to left (H:help last) as the status line fills;
# __bu_tv_render_status puts the keys for the current state in front, and
# the row actions (--action) in front of those, ahead of this separator
declare -g -r __BU_TV_HINT_SEP='·'
declare -g -r __BU_TV_HINTS_TABLE='q:quit /:search s:sort w:wide Enter:detail m:mouse &:filter H:help'
declare -g -r __BU_TV_HINTS_DETAIL='j/k:scroll J/K:record n/N:match q:back H:help'
declare -g -r __BU_TV_HINTS_HELP='j/k:scroll q:back'

# Help overlay text: at most 60 characters per line
declare -g -r -a __BU_TV_HELP_LINES=(
    'Table'
    '  j k ↑ ↓            cursor down / up'
    '  h l ← →            cursor left / right'
    '  g G                first / last row'
    '  0 $ Home End       first / last column'
    '  Space b            page down / up (also PgDn PgUp)'
    '  Shift-↓ Shift-↑    page down / up'
    '  Shift-→ Shift-←    page columns right / left'
    '  Ctrl-→ Ctrl-←      page columns right / left'
    '  Ctrl-D Ctrl-U      half page down / up'
    '  s S                sort column (toggle / descending)'
    '  w W                widen column / all columns'
    '  f                  freeze / unfreeze column (pin left)'
    '  - +                hide column / bring hidden back'
    '  < >                move column left / right'
    '  c                  toggle the column sidebar'
    '  p                  preview pane on / off (tmux/zellij)'
    '  Enter              record detail'
    '  Ctrl-L             re-measure the terminal'
    '  m                  toggle mouse reporting'
    '  H F1               this help'
    '  q Q                quit'
    ''
    'Mouse (m off allows the terminal to select text)'
    '  click              move the cursor to the cell'
    '  double-click       record detail'
    '  header click       select the column'
    '  sidebar click      select the column (or scroll the list)'
    '  sidebar ⇤ ×        freeze / hide the cursor column'
    '  sidebar drag       move a column; across ╌ to (un)freeze,'
    '                     onto Hidden to hide, out to unhide'
    '  Hidden click       bring that column back'
    '  status hint click  press its key'
    '  wheel              scroll three rows (over a long sidebar:'
    '                     scroll its list)'
    '  scrollbar          click to page, drag the thumb'
    '  in an overlay      wheel scrolls, click goes back'
    ''
    'Cells'
    '  ∅                  null (an empty cell is "")'
    '  ◂ N  N ▸           columns off screen (sidebar hidden)'
    ''
    'Search (literal; an uppercase letter makes it match case)'
    '  / ?                search forward / backward'
    '  n N                next / previous match'
    '  &                  filter rows (empty: all rows)'
    '  Esc                clear the search, then the filter'
    '  Backspace Ctrl-U   delete a character / clear (prompt)'
    '  Enter Esc          accept / cancel (prompt)'
    ''
    'Detail'
    '  j k ↑ ↓            scroll'
    '  Space b g G        page down / up, top / bottom'
    '  J K                next / previous record'
    '  n N                next / previous match'
    '  q Esc Enter        back to the table'
)

# Help shown by the overlay: the fixed lines plus the configured row actions
# (bu_tv_set_action)
declare -g -a _TV_HELP_LINES=("${__BU_TV_HELP_LINES[@]}")

# Padding pools — slice with ${__BU_TV_SPACES:0:N} instead of per-cell append
# loops.  Grown by doubling (__bu_tv_ensure_pools) if a column exceeds the pool.
declare -g __BU_TV_SPACES=
declare -g __BU_TV_DASHES=
# 64 spaces, quadrupled to 256
__BU_TV_SPACES="                                                                "
__BU_TV_SPACES+=${__BU_TV_SPACES}${__BU_TV_SPACES}${__BU_TV_SPACES}
__BU_TV_DASHES=${__BU_TV_SPACES// /-}

# *Description*:
# Grow the space/dash padding pools (by doubling) until they hold at least
# N characters.
#
# *Params*:
# - `$1`: Required pool size
__bu_tv_ensure_pools()
{
    local -i need=$1
    while (( ${#__BU_TV_SPACES} < need ))
    do
        __BU_TV_SPACES+=$__BU_TV_SPACES
        __BU_TV_DASHES+=$__BU_TV_DASHES
    done
}

# ── Helpers ──────────────────────────────────────────────────────────────

# *Description*:
# Strip ANSI escape sequences from a string in place.  Handles both CSI
# sequences (ESC [ params letter — colors, bold, reverse) and charset
# selection sequences (ESC ( X / ESC ) X, e.g. the \e(B emitted by
# tput sgr0 as part of BU_TPUT_RESET).
#
# *Params*:
# - `$1`: Nameref to the variable to strip
__bu_tv_strip_ansi()
{
    local -n __bu_tv_strip_ref=$1
    local -r __bu_tv_ansi_re=$'\e'"(\\[[0-9;]*[a-zA-Z]|[()].)"
    while [[ $__bu_tv_strip_ref =~ $__bu_tv_ansi_re ]]
    do
        __bu_tv_strip_ref=${__bu_tv_strip_ref//"${BASH_REMATCH[0]}"/}
    done
}

# *Description*:
# Number of data rows on screen: everything but the header, separator and
# status rows.
#
# *Returns*:
# - `_TV_DATA_ROWS`
declare -g -i _TV_DATA_ROWS=1
__bu_tv_data_rows()
{
    _TV_DATA_ROWS=$((_TV_TERM_ROWS - 3))
    (( _TV_DATA_ROWS < 1 )) && _TV_DATA_ROWS=1
    return 0
}

# *Description*:
# Read all JSONL from stdin into _TV_ROWS.  Skips blank lines.
#
# *Returns*:
# - Sets _TV_ROWS[] and _TV_NUM_ROWS.  _TV_NUM_ROWS = 0 on empty input.
__bu_tv_read_stdin()
{
    _TV_ROWS=()
    _TV_NUM_ROWS=0
    local line
    while IFS= read -r line || [[ -n "$line" ]]
    do
        [[ -z "$line" ]] && continue
        _TV_ROWS+=("$line")
        _TV_NUM_ROWS=$((_TV_NUM_ROWS + 1))
    done
}

# *Description*:
# Extract column keys and display labels.
#
# *Params*:
# - `$1`: Optional comma-separated column spec (key:Label,...).
#         Empty → auto-detect from first record's keys.
#
# *Returns*:
# - Sets _TV_COLUMNS[], _TV_HEADERS[], _TV_NUM_COLS.
__bu_tv_extract_columns()
{
    local spec=$1
    _TV_COLUMNS=()
    _TV_HEADERS=()
    _TV_NUM_COLS=0

    if [[ -n "$spec" ]]
    then
        __bu_out_colspecs_to_json "$spec" || return 1
        local key header
        while IFS=$'\t' read -r key header
        do
            _TV_COLUMNS+=("$key")
            _TV_HEADERS+=("$header")
            _TV_NUM_COLS=$((_TV_NUM_COLS + 1))
        done < <("$BU_OUT_JQ" -r '.[] | "\(.key)\t\(.header)"' <<<"$BU_RET")
    elif (( _TV_NUM_ROWS > 0 ))
    then
        local key
        while IFS= read -r key
        do
            _TV_COLUMNS+=("$key")
            _TV_HEADERS+=("$key")
            _TV_NUM_COLS=$((_TV_NUM_COLS + 1))
        done < <("$BU_OUT_JQ" -r 'keys_unsorted[]' <<<"${_TV_ROWS[0]}")
    fi
}

# *Description*:
# Rebuild the cell cache and compute column widths in a single jq pass.
#
# Each cell is escaped individually (`[.] | @tsv`: tab, newline, CR and
# backslash become two-character escapes), a literal U+0001 or U+0002
# becomes the six characters `\u0001` / `\u0002`, and null becomes a lone
# U+0002 (__BU_TV_NULL, drawn as a dim ∅), so U+0001 can delimit cells.
# jq emits:
# 1. the per-column maximum visible width (ANSI stripped, escaped text
#    measured, null as empty)
# 2. per column, 1 if every non-null value is a number (right-aligned)
# 3. every cell of every row joined by U+0001, plus a trailing sentinel
# 4. one line per row with that row's ANSI-stripped cells joined by U+0001
#    (the search and filter haystack), then a final sentinel line
# U+0001 is non-whitespace IFS, so `read -a` keeps interior empty cells;
# the sentinels protect a trailing empty cell and a trailing empty row line
# (which $(...) would strip).  Ends by re-applying the row filter.
#
# *Params*:
# - None.  Reads _TV_ROWS[], _TV_COLUMNS[], _TV_NUM_ROWS, _TV_NUM_COLS.
#
# *Returns*:
# - Sets _TV_CELLS[], _TV_ROW_TEXT[], _TV_COL_CONTENT_W[], _TV_COL_NUMERIC[],
#   _TV_COL_FULL_WIDTHS[], _TV_COL_WIDTHS[] and the row view.
# - 1 with all of them cleared if the parsed cell count is not rows x cols
#   (a shifted table must never be rendered).
__bu_tv_rebuild_cache()
{
    _TV_CELLS=()
    _TV_ROW_TEXT=()
    _TV_COL_CONTENT_W=()
    _TV_COL_NUMERIC=()
    _TV_COL_FULL_WIDTHS=()
    _TV_COL_WIDTHS=()
    if (( _TV_NUM_ROWS == 0 || _TV_NUM_COLS == 0 ))
    then
        __bu_tv_apply_filter
        return 0
    fi

    # ── Build jq arg list and expression ──────────────────────────────
    local -a jq_args=()
    local jq_keys= sep=
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        jq_args+=('--arg' "c$j" "${_TV_COLUMNS[$j]}")
        jq_keys+="$sep.[\$c$j]"
        sep=,
    done

    # `// ""` would blank `false` too; only null is special.  Only cells
    # that contain the delimiters or ESC go through the (slow) regex passes.
    local jq_expr
    printf -v jq_expr '%s' \
        'map([' "$jq_keys" ']) as $raw' \
        ' | ($raw | map(map(if . == null then "\u0002" else tostring | [.] | @tsv' \
        ' | if contains("\u0001") or contains("\u0002")' \
        ' then gsub("\u0001"; "\\u0001") | gsub("\u0002"; "\\u0002") else . end end))) as $rows' \
        ' | ($rows | map(map(if . == "\u0002" then "" elif contains("\u001b")' \
        ' then gsub("\u001b\\[[0-9;]*[A-Za-z]|\u001b[()]."; "") else . end))) as $plain' \
        ' | ([range(' "$_TV_NUM_COLS" ') as $j | [$plain[][$j] | length]' \
        ' | max] | map(tostring) | join(" ")),' \
        ' ([range(' "$_TV_NUM_COLS" ') as $j | [$raw[][$j] | select(. != null) | type]' \
        ' | if length > 0 and all(. == "number") then "1" else "0" end] | join(" ")),' \
        ' ([$rows[][]] + ["."] | join("\u0001")),' \
        ' ($plain[] | join("\u0001")), "."'

    local out
    out=$(printf '%s\n' "${_TV_ROWS[@]}" | "$BU_OUT_JQ" -r -s "${jq_args[@]}" "$jq_expr")

    # One here-string, not ${out%%$'\n'*}: that expansion is quadratic in
    # the output size
    {
        read -r -a _TV_COL_CONTENT_W
        read -r -a _TV_COL_NUMERIC
        IFS=$'\x01' read -r -a _TV_CELLS
        mapfile -t _TV_ROW_TEXT
    } <<<"$out"
    # Drop the sentinels
    (( ${#_TV_CELLS[@]} )) && unset '_TV_CELLS[-1]'
    if (( ${#_TV_ROW_TEXT[@]} )) && [[ "${_TV_ROW_TEXT[-1]}" == . ]]
    then
        unset '_TV_ROW_TEXT[-1]'
    else
        _TV_ROW_TEXT=()
    fi

    local -i expected=$((_TV_NUM_ROWS * _TV_NUM_COLS))
    if (( ${#_TV_CELLS[@]} != expected || ${#_TV_COL_CONTENT_W[@]} != _TV_NUM_COLS \
        || ${#_TV_COL_NUMERIC[@]} != _TV_NUM_COLS || ${#_TV_ROW_TEXT[@]} != _TV_NUM_ROWS ))
    then
        bu_log_err "bu view-table: parsed ${#_TV_CELLS[@]} cells, ${#_TV_COL_CONTENT_W[@]} widths and ${#_TV_ROW_TEXT[@]} rows, expected $expected cells ($_TV_NUM_ROWS rows x $_TV_NUM_COLS cols) and $_TV_NUM_COLS widths"
        _TV_CELLS=()
        _TV_ROW_TEXT=()
        _TV_COL_CONTENT_W=()
        _TV_COL_NUMERIC=()
        _TV_COL_WIDTHS=()
        _TV_VIEW=()
        _TV_NUM_VIEW=0
        return 1
    fi

    __bu_tv_full_widths
    __bu_tv_apply_filter
    return 0
}

# *Description*:
# Untruncated column widths: the max of the content and the header, plus 2
# on the sorted column for its header arrow.  Then re-derives the effective
# widths.
#
# *Returns*:
# - Sets _TV_COL_FULL_WIDTHS[] and (via __bu_tv_compute_widths)
#   _TV_COL_WIDTHS[].
__bu_tv_full_widths()
{
    _TV_COL_FULL_WIDTHS=()
    local -i j wid hdr
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        wid=${_TV_COL_CONTENT_W[j]:-0}
        hdr=${#_TV_HEADERS[j]}
        [[ -n "$_TV_SORT_COL" && "${_TV_COLUMNS[j]}" == "$_TV_SORT_COL" ]] && hdr=$((hdr + 2))
        (( hdr > wid )) && wid=$hdr
        _TV_COL_FULL_WIDTHS+=("$wid")
    done
    __bu_tv_compute_widths
}

# *Description*:
# Rebuild the row view from _TV_FILTER_QUERY: the data rows whose search
# haystack (ANSI-stripped cells) contains it, in data order.  Literal
# substring, smart case (as search).  No filter is every row.
#
# *Returns*:
# - `_TV_VIEW` (view index → data row index) and `_TV_NUM_VIEW`
__bu_tv_apply_filter()
{
    _TV_VIEW=()
    local -i i
    if [[ -z "$_TV_FILTER_QUERY" ]]
    then
        for (( i = 0; i < _TV_NUM_ROWS; i++ ))
        do
            _TV_VIEW[i]=$i
        done
    else
        local needle=$_TV_FILTER_QUERY fold=true text
        if [[ "$needle" == *[[:upper:]]* ]]
        then
            fold=false
        else
            needle=${needle,,}
        fi
        for (( i = 0; i < _TV_NUM_ROWS; i++ ))
        do
            text=${_TV_ROW_TEXT[i]:-}
            "$fold" && text=${text,,}
            [[ $text == *"$needle"* ]] && _TV_VIEW+=("$i")
        done
    fi
    _TV_NUM_VIEW=${#_TV_VIEW[@]}
    return 0
}

# *Description*:
# Position of a data row in the view, or of the first view row after it
# (the view is in data order), or the last view row past the end.
#
# *Params*:
# - `$1`: Data row index
#
# *Returns*:
# - `_TV_FOUND_IDX`: View index (0 when the view is empty)
__bu_tv_view_find()
{
    local -r -i data=$1
    local -i lo=0 hi=$_TV_NUM_VIEW mid
    while (( lo < hi ))
    do
        mid=$(((lo + hi) / 2))
        if (( _TV_VIEW[mid] < data ))
        then
            lo=$((mid + 1))
        else
            hi=$mid
        fi
    done
    (( lo >= _TV_NUM_VIEW )) && lo=$((_TV_NUM_VIEW - 1))
    (( lo < 0 )) && lo=0
    _TV_FOUND_IDX=$lo
    return 0
}

# *Description*:
# Put the cursor back on a record after the view changed (filter, sort):
# on its row if still in view, else the nearest one after it, at the same
# distance from the top of the screen.
#
# *Params*:
# - `$1`: Data row index (-1: first row)
# - `$2`: Screen row of the cursor relative to the row offset
__bu_tv_place_record()
{
    local -i -r data=$1 rel=$2
    _TV_CUR_ROW=0
    if (( data >= 0 ))
    then
        __bu_tv_view_find "$data"
        _TV_CUR_ROW=$_TV_FOUND_IDX
    fi
    _TV_ROW_OFFSET=$((_TV_CUR_ROW - rel))
    __bu_tv_clamp_offsets
}

# *Description*:
# Data row under the cursor, or -1 when the view is empty.
#
# *Returns*:
# - `_TV_FOUND_IDX`
__bu_tv_cursor_data()
{
    _TV_FOUND_IDX=-1
    (( _TV_NUM_VIEW > 0 )) && _TV_FOUND_IDX=${_TV_VIEW[_TV_CUR_ROW]:--1}
    return 0
}

# *Description*:
# Derive the effective column widths: min(full, cap) with a floor of 4.
# The cap is _TV_MAX_WIDTH, or the width left beside the scrollbar minus 2
# for an expanded column, and never more than that (with its 2-column gap a
# column must always fit alone, or nothing renders).  Call it again
# whenever the terminal size changes.
#
# *Returns*:
# - Sets _TV_COL_WIDTHS[] and _TV_MAX_EFF_W.
__bu_tv_compute_widths()
{
    _TV_COL_WIDTHS=()
    _TV_MAX_EFF_W=0
    __bu_tv_scrollbar_width
    local -r -i term_cap=$((_TV_TERM_COLS - _TV_SCROLLBAR_W - 2))
    local -i j w cap
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        w=${_TV_COL_FULL_WIDTHS[j]:-0}
        cap=$_TV_MAX_WIDTH
        [[ "${_TV_COL_EXPANDED[j]:-false}" == true ]] && cap=$term_cap
        (( cap > term_cap )) && cap=$term_cap
        (( w > cap )) && w=$cap
        (( w < 4 )) && w=4
        _TV_COL_WIDTHS+=("$w")
        (( w > _TV_MAX_EFF_W )) && _TV_MAX_EFF_W=$w
    done
    return 0
}

# *Description*:
# Prepare the search needle from _TV_SEARCH_QUERY.  Smart case: a query
# with an uppercase character matches case-sensitively, otherwise both the
# needle and the haystack are lowercased.
#
# *Returns*:
# - Sets _TV_SEARCH_NEEDLE and _TV_SEARCH_FOLD.
__bu_tv_query_prepare()
{
    if [[ "$_TV_SEARCH_QUERY" == *[[:upper:]]* ]]
    then
        _TV_SEARCH_FOLD=false
        _TV_SEARCH_NEEDLE=$_TV_SEARCH_QUERY
    else
        _TV_SEARCH_FOLD=true
        _TV_SEARCH_NEEDLE=${_TV_SEARCH_QUERY,,}
    fi
    return 0
}

# *Description*:
# Find every non-overlapping occurrence of the search needle in a string,
# left to right.  Literal match (no glob or regex), smart case.  Pure bash.
#
# *Params*:
# - `$1`: Text to search (no ANSI escapes)
#
# *Returns*:
# - `_TV_HITS`: Ascending start offsets (empty without a query)
__bu_tv_find_hits()
{
    _TV_HITS=()
    local -r needle=$_TV_SEARCH_NEEDLE
    [[ -z "$needle" ]] && return 0
    local rest=$1
    [[ "$_TV_SEARCH_FOLD" == true ]] && rest=${rest,,}
    local -i -r qlen=${#needle}
    local -i pos=0 idx
    local prefix
    while [[ $rest == *"$needle"* ]]
    do
        # %% strips the longest suffix starting at the needle, leaving the
        # literal prefix before the first occurrence
        prefix=${rest%%"$needle"*}
        idx=${#prefix}
        _TV_HITS+=($((pos + idx)))
        pos=$((pos + idx + qlen))
        rest=${rest:idx+qlen}
    done
    return 0
}

# *Description*:
# Slice [from, to) of a string, drawing the parts covered by _TV_HITS in
# the hit attribute (black on yellow).  Hits are clipped to the slice.  After each hit the
# caller's base attributes are re-applied explicitly (never reverse-off),
# so a hit stays visible inside a reversed or coloured span.
#
# *Params*:
# - `$1`: Text (no ANSI escapes)
# - `$2`: Slice start
# - `$3`: Slice end (exclusive)
# - `$4`: Attributes to re-apply after a hit, starting with a reset
#
# *Returns*:
# - `_TV_PAINT`
__bu_tv_paint()
{
    local -r text=$1 base=$4
    local -i -r from=$2 to=$3 qlen=${#_TV_SEARCH_NEEDLE}
    local -i p=$from s e
    _TV_PAINT=
    for s in "${_TV_HITS[@]}"
    do
        e=$((s + qlen))
        (( e <= from )) && continue
        (( s >= to )) && break
        (( s < from )) && s=$from
        (( e > to )) && e=$to
        _TV_PAINT+=${text:p:s-p}$_TV_HIT_ATTR${text:s:e-s}$base
        p=$e
    done
    _TV_PAINT+=${text:p:to-p}
    return 0
}

# *Description*:
# Resolve the colour settings, honouring NO_COLOR (no-color.org): when it
# is set and not empty, the default colour spec is "none" and search hits
# are bold underlined reverse instead of black on yellow.  An explicit spec
# wins.
#
# *Params*:
# - `$1`: Colour spec, or empty for the default ("auto")
#
# *Returns*:
# - `BU_RET`: The spec to build; sets `_TV_HIT_ATTR`
__bu_tv_resolve_colors()
{
    local spec=$1
    _TV_HIT_ATTR=$__BU_TV_HIT
    if [[ -n "${NO_COLOR:-}" ]]
    then
        _TV_HIT_ATTR=$__BU_TV_HIT_NO_COLOR
        [[ -z "$spec" ]] && spec=none
    fi
    BU_RET=${spec:-auto}
    return 0
}

# *Description*:
# Build a colors map from a --colors spec or "auto" rainbow.
#
# *Params*:
# - `$1`: Color spec string (same as bu_format_table --colors), "auto"
#         for rainbow, or empty / "none" for no colors
#
# *Returns*:
# - Sets _TV_COLORS assoc array.
__bu_tv_build_colors()
{
    local spec=$1
    _TV_COLORS=()
    [[ -z "$spec" || "$spec" == none ]] && return 0

    if [[ "$spec" == auto ]]
    then
        local -i i
        local cname cvar
        for (( i = 0; i < _TV_NUM_COLS; i++ ))
        do
            cname=${__BU_OUT_RAINBOW[$((i % ${#__BU_OUT_RAINBOW[@]}))]}
            cvar=BU_TPUT_${cname^^}
            _TV_COLORS["${_TV_COLUMNS[$i]}"]=${!cvar}
        done
    else
        __bu_out_colors_to_json "$spec" || return 1
        local key ansi
        while IFS=$'\t' read -r key ansi
        do
            _TV_COLORS["$key"]=$ansi
        done < <("$BU_OUT_JQ" -r 'to_entries[] | "\(.key)\t\(.value)"' <<<"$BU_RET")
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# Terminal management
# ═══════════════════════════════════════════════════════════════════════════

# *Description*:
# Install the viewer's full trap set.  Called at setup and again on resume
# after a stop.  terminal_restore clears all of them.
#
# Every trap only sets a flag; __bu_tv_process_signals does the work from
# the event loop.  The key reader blocks in short `read -t` slices, and
# bash runs a pending trap inside that read: when the slice's timer expires
# while the trap is still running, bash abandons the trap midway (e.g.
# during a $(stty ...) fork, which is slow under load).  A single
# assignment leaves nothing to abandon.
__bu_tv_install_traps()
{
    # Standard TUI practice: ignore SIGTTOU for the viewer's lifetime so a
    # stty/tcsetattr or tty write from a transiently-backgrounded state
    # proceeds instead of default-STOPping the whole pipeline.
    trap '' SIGTTOU
    trap '_TV_QUIT=true' SIGINT SIGTERM
    trap '__bu_tv_cleanup_exit' EXIT
    trap '_TV_RESIZE_PENDING=true' SIGWINCH
    trap '_TV_SUSPEND_PENDING=true' SIGTSTP
    trap '_TV_RESUME_PENDING=true' SIGCONT
}

# *Description*:
# Enter raw terminal mode: alternate screen, hide cursor, mouse reporting
# (unless toggled off), non-canonical input, install signal traps.
# Measures the terminal and derives the column widths (the cache is built
# before the size is known).
#
# *Returns*:
# - 1 without touching the terminal if our process group is not the tty's
#   foreground group (a loud failure instead of a silent SIGTTOU stop).
__bu_tv_terminal_setup()
{
    # Foreground guard: if our pgid is not the tty's foreground pgid, the
    # stty below would deliver SIGTTOU and the kernel would silently stop
    # the entire pipeline.  Refuse to start instead.
    local my_pgid tty_pgid
    my_pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
    tty_pgid=$(ps -o tpgid= -p $$ 2>/dev/null | tr -d ' ')
    if [[ -n "$my_pgid" && -n "$tty_pgid" && "$my_pgid" != "$tty_pgid" ]]
    then
        bu_log_err "bu view-table: process group $my_pgid is not the terminal's foreground group ($tty_pgid)"
        bu_log_err "Run it in the foreground (e.g. '... | bu view-table' in a fresh shell)"
        return 1
    fi

    _TV_SAVED_STTY=$(stty -g 2>/dev/null) || _TV_SAVED_STTY=
    stty -echo -icanon 2>/dev/null || true

    printf '%s' "$__BU_TV_ALT_SCREEN_ON"
    printf '%s' "$__BU_TV_CURSOR_HIDE"
    "$_TV_MOUSE" && printf '%s' "$__BU_TV_MOUSE_ON"
    printf '%s%s' "$__BU_TV_CURSOR_HOME" "$__BU_TV_CLEAR_SCREEN"

    __bu_tv_update_dimensions
    __bu_tv_compute_widths

    __bu_tv_install_traps
    return 0
}

# *Description*:
# Leave the TUI terminal state: mouse reporting off, show cursor, exit
# alternate screen, restore saved stty settings.  Does NOT clear traps —
# used by both the final restore (EXIT trap) and the SIGTSTP suspend path
# (which must keep SIGCONT armed).  Mouse reporting is switched off even
# when toggled off already, so a shell is never left in mouse mode.
__bu_tv_terminal_leave_tui()
{
    printf '%s' "$__BU_TV_MOUSE_OFF"
    printf '%s' "$__BU_TV_CURSOR_SHOW"
    printf '%s' "$__BU_TV_ALT_SCREEN_OFF"

    if [[ -n "$_TV_SAVED_STTY" ]]
    then
        stty "$_TV_SAVED_STTY" 2>/dev/null || true
    fi
}

# *Description*:
# Restore terminal to its original state on exit: clear every trap the
# viewer installed (including TSTP/CONT/TTOU), then leave the TUI state.
__bu_tv_terminal_restore()
{
    trap - SIGINT SIGTERM SIGWINCH SIGTSTP SIGCONT SIGTTOU EXIT
    [[ -n "$_TV_ACTION_OUT" ]] && rm -f "$_TV_ACTION_OUT"
    __bu_tv_preview_close
    __bu_tv_terminal_leave_tui
}

# *Description*:
# Act on the flags the traps set.  Called from the event loop (and the
# search prompt) before each render, outside any trap.  Each flag is
# cleared before its work so a signal arriving meanwhile is handled on the
# next pass.
#
# - Suspend (Ctrl-Z): restore the terminal so the shell prompt is usable
#   while stopped, then SIGSTOP ourselves (uncatchable, so it always stops).
#   Execution continues here after fg, which also counts as a resume.
# - Resume (fg, or SIGCONT after an external stop): re-arm the traps,
#   re-enter raw mode, alternate screen and mouse reporting, and re-measure.
# - Resize: re-measure (size, widths, offsets, detail wrapping).
__bu_tv_process_signals()
{
    if "$_TV_SUSPEND_PENDING"
    then
        _TV_SUSPEND_PENDING=false
        __bu_tv_terminal_leave_tui
        kill -SIGSTOP $$
        _TV_RESUME_PENDING=true
    fi
    if "$_TV_RESUME_PENDING"
    then
        _TV_RESUME_PENDING=false
        __bu_tv_install_traps
        stty -echo -icanon 2>/dev/null || true
        printf '%s' "$__BU_TV_ALT_SCREEN_ON"
        printf '%s' "$__BU_TV_CURSOR_HIDE"
        "$_TV_MOUSE" && printf '%s' "$__BU_TV_MOUSE_ON"
        _TV_RESIZE_PENDING=true
    fi
    if "$_TV_RESIZE_PENDING"
    then
        _TV_RESIZE_PENDING=false
        __bu_tv_remeasure
        # The preview pane shares the width: redraw it at its new size
        _TV_PREVIEW_STALE=true
    fi
    return 0
}

# *Description*:
# EXIT trap handler — delegates to terminal restore.
__bu_tv_cleanup_exit()
{
    __bu_tv_terminal_restore
}

# *Description*:
# Update _TV_TERM_ROWS and _TV_TERM_COLS from current terminal size.
#
# Asks the tty itself (stty size).  Not tput: inside $(...) with stderr
# discarded, tput sees no terminal on stdout or stderr and silently reports
# the terminfo default (80x24 for xterm) with exit status 0.  COLUMNS/LINES
# are unexported shell variables, so the cmdlet process rarely has them.
__bu_tv_update_dimensions()
{
    _TV_TERM_COLS=80
    _TV_TERM_ROWS=24
    [[ -n "${COLUMNS:-}" ]] && _TV_TERM_COLS=$COLUMNS
    [[ -n "${LINES:-}" ]] && _TV_TERM_ROWS=$LINES
    # 2>/dev/null first so a failed /dev/tty open is silenced too
    local size= rows= cols=
    size=$(stty size 2>/dev/null </dev/tty) || size=
    # No `read` here: if this ever runs inside a trap again, a nested read
    # builtin clears the interrupted `read -t` timer in __bu_tv_read_key,
    # which then blocks until the next key
    rows=${size%% *}
    cols=${size##* }
    [[ "$rows" =~ ^[0-9]+$ ]] && _TV_TERM_ROWS=$rows
    [[ "$cols" =~ ^[0-9]+$ ]] && _TV_TERM_COLS=$cols
    if (( _TV_TERM_COLS < 20 )); then _TV_TERM_COLS=80; fi
    if (( _TV_TERM_ROWS < 10 )); then _TV_TERM_ROWS=24; fi
}

# *Description*:
# Re-read the terminal size and re-derive everything that depends on it:
# column widths, offsets and, when the detail overlay is (or will be
# returned to) on screen, its wrapping.  Used on resize, resume and Ctrl-L.
__bu_tv_remeasure()
{
    __bu_tv_update_dimensions
    __bu_tv_compute_widths
    __bu_tv_clamp_offsets
    if [[ "$_TV_MODE" == detail || ( "$_TV_MODE" == help && "$_TV_HELP_RETURN" == detail ) ]]
    then
        __bu_tv_build_detail
    fi
    __bu_tv_overlay_clamp
    return 0
}

# *Description*:
# Split the screen width between the table, the scrollbar and the column
# sidebar, left to right, then work out the frozen prefix.  The scrollbar (a gap and the bar) is reserved
# only while the rows overflow the data area.  The sidebar is as wide as
# the longest column label (capped) plus border, cursor marker and sort
# arrow, and is hidden when the table would be left too narrow for its
# widest column plus gap (so every column still fits on screen alone).
#
# *Returns*:
# - Sets _TV_TABLE_COLS, _TV_SCROLLBAR_W, _TV_SIDEBAR_W (0 = hidden) and
#   _TV_SIDEBAR_NAME_W.
declare -g -r -i __BU_TV_SIDEBAR_MAX_NAME=20
__bu_tv_update_layout()
{
    __bu_tv_scrollbar_width
    _TV_TABLE_COLS=$((_TV_TERM_COLS - _TV_SCROLLBAR_W))
    _TV_SIDEBAR_W=0
    _TV_SIDEBAR_NAME_W=0
    if "$_TV_SIDEBAR" && (( _TV_NUM_COLS > 0 ))
    then
        # Wide enough for the "Columns" title: marker + name + " ↑" >= 7
        local -i name_w=4 j
        for (( j = 0; j < _TV_NUM_COLS; j++ ))
        do
            (( ${#_TV_HEADERS[j]} > name_w )) && name_w=${#_TV_HEADERS[j]}
        done
        for j in "${!_TV_HIDDEN[@]}"
        do
            __bu_tv_hidden_label "$j"
            (( ${#_TV_FOUND_LABEL} > name_w )) && name_w=${#_TV_FOUND_LABEL}
        done
        (( name_w > __BU_TV_SIDEBAR_MAX_NAME )) && name_w=$__BU_TV_SIDEBAR_MAX_NAME

        # "│ " + marker + name + " ↑"
        local -i width=$((2 + 1 + name_w + 2))
        if (( _TV_TABLE_COLS - width >= _TV_MAX_EFF_W + 2 ))
        then
            _TV_SIDEBAR_NAME_W=$name_w
            _TV_SIDEBAR_W=$width
            _TV_TABLE_COLS=$((_TV_TABLE_COLS - width))
        fi
    fi
    __bu_tv_update_frozen
    return 0
}

# *Description*:
# Put the frozen prefix [0, _TV_FROZEN_N) in effect when it leaves room
# for the widest scrolling column beside it; otherwise suspend it (the
# columns scroll as if nothing were frozen) until the table is wide enough.
#
# *Returns*:
# - `_TV_FROZEN_EFF`, `_TV_FROZEN_COST`
__bu_tv_update_frozen()
{
    _TV_FROZEN_EFF=0
    _TV_FROZEN_COST=0
    local -i n=$_TV_FROZEN_N j cost=0 widest=0
    (( n > _TV_NUM_COLS - 1 )) && n=$((_TV_NUM_COLS - 1))
    (( n <= 0 )) && return 0
    for (( j = 0; j < n; j++ ))
    do
        cost=$((cost + _TV_COL_WIDTHS[j] + 2))
    done
    for (( j = n; j < _TV_NUM_COLS; j++ ))
    do
        (( _TV_COL_WIDTHS[j] > widest )) && widest=${_TV_COL_WIDTHS[j]}
    done
    (( cost + widest + 2 > _TV_TABLE_COLS )) && return 0
    _TV_FROZEN_EFF=$n
    _TV_FROZEN_COST=$cost
    return 0
}

# *Description*:
# Reserve two screen columns (a gap and the bar) for the scrollbar while
# the rows overflow the data area; nothing otherwise.
#
# *Returns*:
# - `_TV_SCROLLBAR_W`: 2 or 0
__bu_tv_scrollbar_width()
{
    __bu_tv_data_rows
    _TV_SCROLLBAR_W=0
    (( _TV_NUM_VIEW > _TV_DATA_ROWS )) && _TV_SCROLLBAR_W=2
    return 0
}

# *Description*:
# Scrollbar thumb geometry on a track of the data rows.  Height is
# data_rows^2 / total_rows, at least 1 and never the whole track; the top
# maps the row offset onto the rest of the track, rounded.
#
# *Returns*:
# - `_TV_SB_TOP`, `_TV_SB_HEIGHT`, `_TV_SB_ROOM` (track rows the top can
#   move over) and `_TV_SB_MAX_OFF` (largest row offset)
__bu_tv_scrollbar_thumb()
{
    __bu_tv_data_rows
    local -r -i track=$_TV_DATA_ROWS
    _TV_SB_MAX_OFF=$((_TV_NUM_VIEW - track))
    (( _TV_SB_MAX_OFF < 0 )) && _TV_SB_MAX_OFF=0
    _TV_SB_HEIGHT=0
    (( _TV_NUM_VIEW > 0 )) && _TV_SB_HEIGHT=$((track * track / _TV_NUM_VIEW))
    (( _TV_SB_HEIGHT >= track )) && _TV_SB_HEIGHT=$((track - 1))
    (( _TV_SB_HEIGHT < 1 )) && _TV_SB_HEIGHT=1
    _TV_SB_ROOM=$((track - _TV_SB_HEIGHT))
    _TV_SB_TOP=0
    if (( _TV_SB_MAX_OFF > 0 ))
    then
        _TV_SB_TOP=$(((_TV_ROW_OFFSET * _TV_SB_ROOM + _TV_SB_MAX_OFF / 2) / _TV_SB_MAX_OFF))
    fi
    return 0
}

# ── Cursor and viewport ──────────────────────────────────────────────────

# *Description*:
# Clamp the cursor into the view, then derive _TV_ROW_OFFSET and
# _TV_COL_OFFSET so the cursor cell is on screen, scrolling the minimum
# amount.  _TV_COL_OFFSET is the first scrolling column, after any frozen
# ones.  Rows: bring the cursor row into view, then pull the offset back
# so no blank rows are left under the last record.  Columns: walk the
# offset right until the cursor column fits (each column takes its width
# plus a 2-column gap, as in the renderer), then left while everything
# from the new left edge to the last column still fits.
__bu_tv_clamp_offsets()
{
    __bu_tv_data_rows
    local -r -i data_rows=$_TV_DATA_ROWS

    (( _TV_CUR_ROW >= _TV_NUM_VIEW )) && _TV_CUR_ROW=$((_TV_NUM_VIEW - 1))
    (( _TV_CUR_ROW < 0 )) && _TV_CUR_ROW=0
    (( _TV_CUR_COL >= _TV_NUM_COLS )) && _TV_CUR_COL=$((_TV_NUM_COLS - 1))
    (( _TV_CUR_COL < 0 )) && _TV_CUR_COL=0

    (( _TV_CUR_ROW < _TV_ROW_OFFSET )) && _TV_ROW_OFFSET=$_TV_CUR_ROW
    (( _TV_CUR_ROW >= _TV_ROW_OFFSET + data_rows )) && _TV_ROW_OFFSET=$((_TV_CUR_ROW - data_rows + 1))
    local -i max_row=$((_TV_NUM_VIEW - data_rows))
    (( _TV_ROW_OFFSET > max_row )) && _TV_ROW_OFFSET=$max_row
    (( _TV_ROW_OFFSET < 0 )) && _TV_ROW_OFFSET=0

    __bu_tv_update_layout

    if (( _TV_NUM_COLS == 0 ))
    then
        _TV_COL_OFFSET=0
        return 0
    fi
    # The offset is the first scrolling column: frozen columns are always
    # on screen and take their share of the width
    local -r -i first=$_TV_FROZEN_EFF
    local -r -i avail=$((_TV_TABLE_COLS - _TV_FROZEN_COST))
    (( _TV_COL_OFFSET >= _TV_NUM_COLS )) && _TV_COL_OFFSET=$((_TV_NUM_COLS - 1))
    (( _TV_COL_OFFSET < first )) && _TV_COL_OFFSET=$first

    local -i j used=0
    if (( _TV_CUR_COL >= first ))
    then
        (( _TV_COL_OFFSET > _TV_CUR_COL )) && _TV_COL_OFFSET=$_TV_CUR_COL
        for (( j = _TV_COL_OFFSET; j <= _TV_CUR_COL; j++ ))
        do
            used=$((used + _TV_COL_WIDTHS[j] + 2))
        done
        while (( used > avail && _TV_COL_OFFSET < _TV_CUR_COL ))
        do
            used=$((used - _TV_COL_WIDTHS[_TV_COL_OFFSET] - 2))
            _TV_COL_OFFSET=$((_TV_COL_OFFSET + 1))
        done
    fi

    used=0
    for (( j = _TV_COL_OFFSET; j < _TV_NUM_COLS; j++ ))
    do
        used=$((used + _TV_COL_WIDTHS[j] + 2))
    done
    while (( _TV_COL_OFFSET > first && used + _TV_COL_WIDTHS[_TV_COL_OFFSET - 1] + 2 <= avail ))
    do
        _TV_COL_OFFSET=$((_TV_COL_OFFSET - 1))
        used=$((used + _TV_COL_WIDTHS[_TV_COL_OFFSET] + 2))
    done
    return 0
}

# *Description*:
# Move the cursor by a row and column delta, then re-clamp.
#
# *Params*:
# - `$1`: Row delta
# - `$2`: Column delta
__bu_tv_move()
{
    _TV_CUR_ROW=$((_TV_CUR_ROW + $1))
    _TV_CUR_COL=$((_TV_CUR_COL + $2))
    __bu_tv_clamp_offsets
}

# *Description*:
# Page rows: move the cursor and the viewport together by a delta.
#
# *Params*:
# - `$1`: Row delta (a page is ±_TV_DATA_ROWS)
__bu_tv_page_rows()
{
    _TV_CUR_ROW=$((_TV_CUR_ROW + $1))
    _TV_ROW_OFFSET=$((_TV_ROW_OFFSET + $1))
    __bu_tv_clamp_offsets
}

# *Description*:
# Offset-driven scrolling (wheel, scrollbar): clamp the row offset to its
# range first, then drag the cursor into the visible window — the reverse
# of the keys, where the window follows the cursor.
#
# *Params*:
# - `$1`: New row offset (clamped)
__bu_tv_scroll_to()
{
    __bu_tv_data_rows
    local -i off=$1
    local -r -i max_off=$((_TV_NUM_VIEW - _TV_DATA_ROWS))
    (( off > max_off )) && off=$max_off
    (( off < 0 )) && off=0
    _TV_ROW_OFFSET=$off
    (( _TV_CUR_ROW < off )) && _TV_CUR_ROW=$off
    (( _TV_CUR_ROW >= off + _TV_DATA_ROWS )) && _TV_CUR_ROW=$((off + _TV_DATA_ROWS - 1))
    __bu_tv_clamp_offsets
}

# *Description*:
# Page the columns right: the first column cut off on the right becomes the
# new left edge and the cursor lands on it.  With nothing cut off this is
# End (cursor on the last column, minimum scroll).  The clamp may pull the
# offset back near the end so the tail fills the screen.
__bu_tv_page_cols_right()
{
    # _TV_VIS_COLS is only refreshed per frame
    __bu_tv_compute_visible_cols
    (( ${#_TV_VIS_COLS[@]} == 0 )) && return 0
    local -r -i last=${_TV_VIS_COLS[-1]}
    if (( last < _TV_NUM_COLS - 1 ))
    then
        _TV_COL_OFFSET=$((last + 1))
        _TV_CUR_COL=$_TV_COL_OFFSET
    else
        _TV_CUR_COL=$((_TV_NUM_COLS - 1))
    fi
    __bu_tv_clamp_offsets
}

# *Description*:
# Page the columns left: the current first visible column becomes the
# rightmost visible one and the cursor lands on the new left edge.  An
# over-wide first column that cannot share the screen with its left
# neighbour still moves one column left.  At column 0 (or the first
# column after the frozen ones) the cursor goes there.
__bu_tv_page_cols_left()
{
    (( _TV_NUM_COLS == 0 )) && return 0
    __bu_tv_update_layout
    local -r -i first=$_TV_COL_OFFSET lo=$_TV_FROZEN_EFF
    local -r -i avail=$((_TV_TABLE_COLS - _TV_FROZEN_COST))
    local -i start=$lo used
    if (( first > lo ))
    then
        start=$first
        used=$((_TV_COL_WIDTHS[first] + 2))
        while (( start > lo && used + _TV_COL_WIDTHS[start - 1] + 2 <= avail ))
        do
            start=$((start - 1))
            used=$((used + _TV_COL_WIDTHS[start] + 2))
        done
        (( start == first )) && start=$((first - 1))
    fi
    _TV_COL_OFFSET=$start
    _TV_CUR_COL=$start
    __bu_tv_clamp_offsets
}

# *Description*:
# Widen (or restore) the cursor column: an expanded column is capped at the
# terminal width minus 2 instead of _TV_MAX_WIDTH.
__bu_tv_toggle_wide()
{
    (( _TV_NUM_COLS == 0 )) && return 0
    if [[ "${_TV_COL_EXPANDED[_TV_CUR_COL]:-false}" == true ]]
    then
        _TV_COL_EXPANDED[_TV_CUR_COL]=false
    else
        _TV_COL_EXPANDED[_TV_CUR_COL]=true
    fi
    __bu_tv_compute_widths
    __bu_tv_clamp_offsets
}

# *Description*:
# Expand every column, or collapse them all if all are already expanded.
__bu_tv_toggle_wide_all()
{
    local value=false
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        if [[ "${_TV_COL_EXPANDED[j]:-false}" != true ]]
        then
            value=true
            break
        fi
    done
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        _TV_COL_EXPANDED[j]=$value
    done
    __bu_tv_compute_widths
    __bu_tv_clamp_offsets
}

# ═══════════════════════════════════════════════════════════════════════════
# Rendering
# ═══════════════════════════════════════════════════════════════════════════

# *Description*:
# Compute the column indices visible in the current viewport, once per
# frame: the frozen columns, then the scrolling ones from the offset.
#
# *Returns*:
# - `_TV_VIS_COLS`: Array of visible column indices
__bu_tv_compute_visible_cols()
{
    __bu_tv_update_layout
    _TV_VIS_COLS=()
    local -i j used=0
    for (( j = 0; j < _TV_FROZEN_EFF; j++ ))
    do
        _TV_VIS_COLS+=($j)
        used=$((used + _TV_COL_WIDTHS[j] + 2))
    done
    j=$_TV_COL_OFFSET
    (( j < _TV_FROZEN_EFF )) && j=$_TV_FROZEN_EFF
    for (( ; j < _TV_NUM_COLS; j++ ))
    do
        (( used + _TV_COL_WIDTHS[j] + 2 > _TV_TABLE_COLS )) && break
        _TV_VIS_COLS+=($j)
        : $((used += _TV_COL_WIDTHS[j] + 2))
    done
    return 0
}

# *Description*:
# Build the formatted text and visible width for a single data cell.
# Pure bash, no forks: reads _TV_CELLS[] directly.
#
# A cell carrying producer ANSI escapes is matched, highlighted and
# truncated on its stripped text whenever a query is active or it must be
# truncated (a query could otherwise match inside `\e[31m` and splice the
# highlight into the escape); otherwise its escapes are kept, with each
# reset re-applying the row and cell attributes.  A hit hidden by
# truncation highlights the ellipsis.  Null is a dim ∅.
#
# *Params*:
# - `$1`: Data row index
# - `$2`: Column index
# - `$3`: Row attribute (e.g. reverse video for the cursor row) or empty
#
# *Returns*:
# - `_TV_FC_TEXT`: Cell text with ANSI styling (color, search highlight)
# - `_TV_FC_VIS_LEN`: Visible width (ANSI excluded); equals the column
#   width when truncated.  Search highlighting does not change it.
__bu_tv_format_cell()
{
    local -i -r row_idx=$1 col_idx=$2
    local -r row_attr=$3
    local -i -r col_w=${_TV_COL_WIDTHS[col_idx]}
    local -r color=${_TV_COLORS[${_TV_COLUMNS[col_idx]}]:-}
    local text=${_TV_CELLS[row_idx * _TV_NUM_COLS + col_idx]:-}
    local -i len
    local kept_esc=false

    if [[ "$text" == "$__BU_TV_NULL" ]]
    then
        _TV_FC_TEXT=$__BU_TV_NULL_CELL$row_attr
        _TV_FC_VIS_LEN=1
        return 0
    fi

    if [[ $text == *$'\e'* ]]
    then
        local plain=$text
        __bu_tv_strip_ansi plain
        len=${#plain}
        if [[ -n "$_TV_SEARCH_NEEDLE" ]] || (( len > col_w ))
        then
            text=$plain
        else
            kept_esc=true
        fi
    else
        len=${#text}
    fi

    # Common path: fits, no query
    if [[ -z "$_TV_SEARCH_NEEDLE" ]] && (( len <= col_w ))
    then
        if "$kept_esc" && [[ -n "$row_attr$color" ]]
        then
            local -r rep=$__BU_TV_RESET$row_attr$color
            text=${text//"$__BU_TV_RESET"/"$rep"}
            text=${text//"$__BU_TV_RESET_SHORT"/"$rep"}
        fi
        _TV_FC_VIS_LEN=$len
        if [[ -n "$color" ]]
        then
            _TV_FC_TEXT=$color$text$__BU_TV_RESET$row_attr
        else
            _TV_FC_TEXT=$text
        fi
        return 0
    fi

    local -i vis=$len
    local ellipsis=
    if (( len > col_w ))
    then
        vis=$((col_w - 1))
        ellipsis='…'
        _TV_FC_VIS_LEN=$col_w
    else
        _TV_FC_VIS_LEN=$len
    fi

    if [[ -n "$_TV_SEARCH_NEEDLE" ]]
    then
        local -r base=$__BU_TV_RESET$row_attr$color
        __bu_tv_find_hits "$text"
        __bu_tv_paint "$text" 0 "$vis" "$base"
        text=$_TV_PAINT
        if [[ -n "$ellipsis" ]] && (( ${#_TV_HITS[@]} )) \
            && (( ${_TV_HITS[-1]} + ${#_TV_SEARCH_NEEDLE} > vis ))
        then
            ellipsis=$_TV_HIT_ATTR$ellipsis$base
        fi
    else
        text=${text:0:vis}
    fi

    if [[ -n "$color" ]]
    then
        _TV_FC_TEXT=$color$text$ellipsis$__BU_TV_RESET$row_attr
    else
        _TV_FC_TEXT=$text$ellipsis
    fi
    return 0
}

# *Description*:
# Render a single table line (header, separator, or data row).
#
# The header draws the cursor column bold and underlined, the others bold,
# and the sorted column with its arrow.  Numeric columns (header included)
# are right-aligned.  A dim divider replaces the gap after the frozen
# columns.  A data row with a row attribute (the cursor row) starts with
# it, keeps its padding inside it out to the table width and ends with a
# reset; its cursor cell (padding included) is drawn in
# __BU_TV_CURSOR_CELL instead, switched in and out with explicit resets.
# Plain rows are right-trimmed.
#
# *Params*:
# - `$1`: Data row index (-1 = header, -2 = separator)
# - `$2`: Row attribute (reverse video for the cursor row) or empty
# - `$3`: Nameref to the output variable
#
# *Returns*:
# - `$3`: Formatted row string
__bu_tv_render_line()
{
    local -i -r row_idx=$1
    local -r row_attr=$2
    local -n __rl_out=$3
    __rl_out=
    local sep= j hdr hattr arrow pad lead_cell=false
    local -i col_w hdr_len width=-2 k=0
    for j in "${_TV_VIS_COLS[@]}"
    do
        col_w=${_TV_COL_WIDTHS[$j]}
        (( col_w > ${#__BU_TV_SPACES} )) && __bu_tv_ensure_pools $col_w
        width=$((width + col_w + 2))
        (( k > 0 && k == _TV_FROZEN_EFF )) && sep=$__BU_TV_FROZEN_GAP
        k=$((k + 1))
        if (( row_idx == -1 ))
        then
            hdr=${_TV_HEADERS[$j]}
            arrow=
            if [[ -n "$_TV_SORT_COL" && "${_TV_COLUMNS[j]}" == "$_TV_SORT_COL" ]]
            then
                arrow=' ↑'
                [[ "$_TV_SORT_DIR" == desc ]] && arrow=' ↓'
            fi
            hdr_len=$((${#hdr} + ${#arrow}))
            if (( hdr_len > col_w ))
            then
                # The ellipsis (and arrow) occupy the last cells: no padding
                hdr="${hdr:0:col_w-${#arrow}-1}…"
                hdr_len=$col_w
            fi
            hattr=$__BU_TV_BOLD
            (( j == _TV_CUR_COL )) && hattr=$__BU_TV_BOLD_UNDERLINE
            pad=${__BU_TV_SPACES:0:col_w-hdr_len}
            if [[ "${_TV_COL_NUMERIC[j]:-0}" == 1 ]]
            then
                __rl_out+=$sep$pad$hattr$hdr$arrow$__BU_TV_RESET
            else
                __rl_out+=$sep$hattr$hdr$arrow$__BU_TV_RESET$pad
            fi
        elif (( row_idx == -2 ))
        then
            __rl_out+=$sep${__BU_TV_DASHES:0:col_w}
        elif [[ -n "$row_attr" ]] && (( j == _TV_CUR_COL ))
        then
            # The cursor cell: its own attribute instead of the row's
            __bu_tv_format_cell "$row_idx" "$j" "$__BU_TV_CURSOR_CELL"
            pad=${__BU_TV_SPACES:0:col_w-_TV_FC_VIS_LEN}
            if (( k == 1 ))
            then
                lead_cell=true
                __rl_out+=$__BU_TV_CURSOR_CELL
            else
                __rl_out+=$sep$__BU_TV_RESET$__BU_TV_CURSOR_CELL
            fi
            if [[ "${_TV_COL_NUMERIC[j]:-0}" == 1 ]]
            then
                __rl_out+=$pad$_TV_FC_TEXT
            else
                __rl_out+=$_TV_FC_TEXT$pad
            fi
            __rl_out+=$__BU_TV_RESET$row_attr
        else
            __bu_tv_format_cell "$row_idx" "$j" "$row_attr"
            pad=${__BU_TV_SPACES:0:col_w-_TV_FC_VIS_LEN}
            if [[ "${_TV_COL_NUMERIC[j]:-0}" == 1 ]]
            then
                __rl_out+=$sep$pad$_TV_FC_TEXT
            else
                __rl_out+=$sep$_TV_FC_TEXT$pad
            fi
        fi
        sep='  '
    done
    if [[ -n "$row_attr" ]]
    then
        local -i pad_w=$((_TV_TABLE_COLS - width))
        (( pad_w < 0 )) && pad_w=0
        (( pad_w > ${#__BU_TV_SPACES} )) && __bu_tv_ensure_pools $pad_w
        # A leading cursor cell carries its own attribute
        "$lead_cell" || __rl_out=$row_attr$__rl_out
        __rl_out+=${__BU_TV_SPACES:0:pad_w}$__BU_TV_RESET
    else
        __rl_out=${__rl_out%"${__rl_out##*[! ]}"}
    fi
}

# *Description*:
# Append "◂ N" / "N ▸" markers to the separator row for the columns
# scrolled off the left (after any frozen ones) and right of the viewport.
# Drawn when the sidebar, which shows the same thing, is hidden.
#
# *Params*:
# - `$1`: Nameref to the frame variable (appended to)
__bu_tv_render_col_markers()
{
    local -n __cm_frame=$1
    (( ${#_TV_VIS_COLS[@]} == 0 )) && return 0
    local -r -i left=$((_TV_COL_OFFSET - _TV_FROZEN_EFF))
    local -r -i right=$((_TV_NUM_COLS - 1 - _TV_VIS_COLS[-1]))
    local text
    if (( left > 0 ))
    then
        __cm_frame+=$'\e[2;'$((_TV_FROZEN_COST + 1))'H'$__BU_TV_BOLD"◂ $left"$__BU_TV_RESET
    fi
    if (( right > 0 ))
    then
        text="$right ▸"
        __cm_frame+=$'\e[2;'$((_TV_TABLE_COLS - ${#text} + 1))'H'$__BU_TV_BOLD$text$__BU_TV_RESET
    fi
    return 0
}

# *Description*:
# Build the sidebar's list, top to bottom: the frozen columns, a divider
# (only while some are frozen), the scrolling columns, a "Hidden" title
# (always, as a drop target) and the hidden columns in the order they were
# hidden.
#
# *Returns*:
# - `_TV_SIDEBAR_LIST_KIND`: per row: col, div, title or hid
# - `_TV_SIDEBAR_LIST_ARG`: column index (col), hidden-stack index (hid),
#   else -1
__bu_tv_sidebar_list()
{
    _TV_SIDEBAR_LIST_KIND=()
    _TV_SIDEBAR_LIST_ARG=()
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        if (( j == _TV_FROZEN_N && j > 0 ))
        then
            _TV_SIDEBAR_LIST_KIND+=(div)
            _TV_SIDEBAR_LIST_ARG+=(-1)
        fi
        _TV_SIDEBAR_LIST_KIND+=(col)
        _TV_SIDEBAR_LIST_ARG+=("$j")
    done
    _TV_SIDEBAR_LIST_KIND+=(title)
    _TV_SIDEBAR_LIST_ARG+=(-1)
    for j in "${!_TV_HIDDEN[@]}"
    do
        _TV_SIDEBAR_LIST_KIND+=(hid)
        _TV_SIDEBAR_LIST_ARG+=("$j")
    done
    return 0
}

# *Description*:
# Label of a hidden column (the fourth field of its _TV_HIDDEN entry).
#
# *Params*:
# - `$1`: Hidden-stack index
#
# *Returns*:
# - `_TV_FOUND_LABEL`
__bu_tv_hidden_label()
{
    local rest=${_TV_HIDDEN[$1]}
    rest=${rest#*$'\x1f'}
    rest=${rest#*$'\x1f'}
    rest=${rest#*$'\x1f'}
    _TV_FOUND_LABEL=${rest%%$'\x1f'*}
}

# *Description*:
# Append the column sidebar to a frame: a "Columns" title and separator on
# screen rows 1-2, then the list (__bu_tv_sidebar_list) on the data rows.
# Columns in the viewport are drawn in reverse video (in their --colors
# color), the rest dimmed; ▸ marks the cursor column (the one s/S sort),
# whose entry ends in the mouse buttons ⇤ (freeze / unfreeze) and × (hide)
# where other entries show the sort arrow ↑/↓.  The frozen columns sit
# above a dim ╌ divider; hidden columns are listed dimmed under the
# Hidden title, each with a +.
# When the list is taller than the data rows it scrolls to keep the
# viewport's columns and the cursor column on screen (or where the wheel
# put it, until the next key), with "↑ N more" / "↓ N more" rows standing
# in for the hidden ends (counting columns; just "more" when only the
# divider or the Hidden title is cut off).  While an entry is dragged off
# its row, the row under the pointer (the title, above the list) is
# underlined.
#
# *Params*:
# - `$1`: Nameref to the frame variable (appended to)
# - `$2`: Number of data rows
#
# *Returns*:
# - `_TV_SIDEBAR_START`, `_TV_SIDEBAR_END`: the list window [start, end)
#   drawn, and `_TV_SIDEBAR_NROWS` the list length
# - `_TV_SIDEBAR_ROW_IDX`: per data row, the list row drawn there, -1 for
#   "↑ N more", -2 for "↓ N more", -3 for blank — for mouse hit-testing
__bu_tv_render_sidebar()
{
    local -n __sb_frame=$1
    local -i avail=$2
    local -i col=$((_TV_TABLE_COLS + _TV_SCROLLBAR_W + 1))
    local -i name_w=$_TV_SIDEBAR_NAME_W
    local -i inner_w=$((_TV_SIDEBAR_W - 2))
    (( inner_w > ${#__BU_TV_SPACES} )) && __bu_tv_ensure_pools $inner_w

    # Underline the drop target while an entry is dragged
    local drop=
    [[ -n "$_TV_SIDEBAR_DRAG" ]] && (( _TV_SIDEBAR_DROP_ROW != -99 )) && drop=$'\e[4m'

    local title=$__BU_TV_BOLD
    [[ -n "$drop" ]] && (( _TV_SIDEBAR_DROP_ROW < 0 )) && title+=$drop
    __sb_frame+=$'\e[1;'$col'H│ '$title'Columns'$__BU_TV_RESET$__BU_TV_CLEAR_LINE
    __sb_frame+=$'\e[2;'$col'H│ '${__BU_TV_DASHES:0:inner_w}$__BU_TV_CLEAR_LINE

    __bu_tv_sidebar_list
    local -i n=${#_TV_SIDEBAR_LIST_KIND[@]}
    # A list too long for the screen, with nothing hidden, leaves out the
    # Hidden title rather than spend an indicator row on it
    if (( n > avail && ${#_TV_HIDDEN[@]} == 0 ))
    then
        n=$((n - 1))
        unset '_TV_SIDEBAR_LIST_KIND[n]' '_TV_SIDEBAR_LIST_ARG[n]'
    fi

    # Visible columns need not be contiguous (frozen ones come first); the
    # window follows the first scrolling one.  A scrolling column's list
    # row is one past its index while the divider is shown.
    local -a is_vis=()
    local -i first_vis=-1 v div=0
    (( _TV_FROZEN_N > 0 )) && div=1
    for v in "${_TV_VIS_COLS[@]}"
    do
        is_vis[v]=1
    done
    if (( ${#_TV_VIS_COLS[@]} > _TV_FROZEN_EFF ))
    then
        first_vis=${_TV_VIS_COLS[_TV_FROZEN_EFF]}
    elif (( ${#_TV_VIS_COLS[@]} ))
    then
        first_vis=${_TV_VIS_COLS[0]}
    fi
    (( first_vis >= _TV_FROZEN_N )) && first_vis=$((first_vis + div))
    local -i cur_row=$_TV_CUR_COL
    (( cur_row >= _TV_FROZEN_N )) && cur_row=$((cur_row + div))

    # Window [start, start + cap) of list rows; the rest of avail is taken
    # by the overflow indicator rows
    local -i start=0 cap=$n
    if (( n > avail ))
    then
        cap=$((avail - 2))
        (( cap < 1 )) && cap=1
        if (( _TV_SIDEBAR_SCROLL >= 0 ))
        then
            start=$_TV_SIDEBAR_SCROLL
        else
            start=$((first_vis - 1))
            (( cur_row >= start + cap )) && start=$((cur_row - cap + 1))
        fi
        (( start > n - cap )) && start=$((n - cap))
        (( start < 0 )) && start=0
        # Reclaim an indicator row the window doesn't need
        if (( start == 0 ))
        then
            cap=$((cap + 1))
        elif (( start + cap == n ))
        then
            start=$((start - 1))
            cap=$((cap + 1))
        fi
    fi
    local -i end=$((start + cap))
    (( end > n )) && end=$n
    _TV_SIDEBAR_START=$start
    _TV_SIDEBAR_END=$end
    _TV_SIDEBAR_NROWS=$n
    _TV_SIDEBAR_ROW_IDX=()

    local -i i li=$start screen_row arg count nw
    local entry name marker suffix style kind divider
    local -i name_len
    printf -v divider '%*s' "$inner_w" ''
    divider=${divider// /╌}
    for (( i = 0; i < avail; i++ ))
    do
        screen_row=$((i + 3))
        if (( i == 0 && start > 0 ))
        then
            count=0
            for (( v = 0; v < start; v++ ))
            do
                [[ "${_TV_SIDEBAR_LIST_KIND[v]}" == col || "${_TV_SIDEBAR_LIST_KIND[v]}" == hid ]] && count=$((count + 1))
            done
            entry="${__BU_TV_DIM}↑ $count more${__BU_TV_RESET}"
            (( count )) || entry="${__BU_TV_DIM}↑ more${__BU_TV_RESET}"
            _TV_SIDEBAR_ROW_IDX[i]=-1
        elif (( li >= end ))
        then
            if (( li < n ))
            then
                count=0
                for (( v = li; v < n; v++ ))
                do
                    [[ "${_TV_SIDEBAR_LIST_KIND[v]}" == col || "${_TV_SIDEBAR_LIST_KIND[v]}" == hid ]] && count=$((count + 1))
                done
                entry="${__BU_TV_DIM}↓ $count more${__BU_TV_RESET}"
                (( count )) || entry="${__BU_TV_DIM}↓ more${__BU_TV_RESET}"
                _TV_SIDEBAR_ROW_IDX[i]=-2
                li=$n
            else
                entry=
                [[ -n "$drop" ]] && (( i == _TV_SIDEBAR_DROP_ROW )) \
                    && entry=$drop${__BU_TV_SPACES:0:inner_w}$__BU_TV_RESET
                _TV_SIDEBAR_ROW_IDX[i]=-3
            fi
        else
            _TV_SIDEBAR_ROW_IDX[i]=$li
            kind=${_TV_SIDEBAR_LIST_KIND[li]}
            arg=${_TV_SIDEBAR_LIST_ARG[li]}
            li=$((li + 1))
            case "$kind" in
            div)
                entry=$__BU_TV_DIM$divider$__BU_TV_RESET
                ;;
            title)
                entry="${__BU_TV_DIM}Hidden ${__BU_TV_DASHES:0:inner_w-7}${__BU_TV_RESET}"
                ;;
            hid)
                __bu_tv_hidden_label "$arg"
                name=$_TV_FOUND_LABEL
                name_len=${#name}
                if (( name_len > name_w ))
                then
                    name="${name:0:name_w-1}…"
                    name_len=$name_w
                fi
                entry="${__BU_TV_DIM} ${name}${__BU_TV_SPACES:0:name_w-name_len} +${__BU_TV_RESET}"
                ;;
            col)
                # The cursor entry gives two name cells to its buttons
                nw=$name_w
                (( arg == _TV_CUR_COL )) && nw=$((name_w - 2))
                name=${_TV_HEADERS[arg]}
                name_len=${#name}
                if (( name_len > nw ))
                then
                    name="${name:0:nw-1}…"
                    name_len=$nw
                fi
                marker=' '
                suffix='  '
                if (( arg == _TV_CUR_COL ))
                then
                    marker='▸'
                    suffix=' ⇤ ×'
                elif [[ "${_TV_COLUMNS[arg]}" == "$_TV_SORT_COL" ]]
                then
                    suffix=' ↑'
                    [[ "$_TV_SORT_DIR" == desc ]] && suffix=' ↓'
                fi
                if [[ -n "${is_vis[arg]:-}" ]]
                then
                    style=${_TV_COLORS[${_TV_COLUMNS[arg]}]:-}$__BU_TV_REVERSE
                else
                    style=$__BU_TV_DIM
                fi
                entry="${style}${marker}${name}${__BU_TV_SPACES:0:nw-name_len}${suffix}${__BU_TV_RESET}"
                ;;
            esac
            [[ -n "$drop" ]] && (( i == _TV_SIDEBAR_DROP_ROW )) && entry=$drop$entry
        fi
        __sb_frame+=$'\e['$screen_row';'$col'H│ '$entry$__BU_TV_CLEAR_LINE
    done
}

# *Description*:
# Append the scrollbar to a frame: on each data row, in the column after
# the table's gap, a dim track or the solid thumb.
#
# *Params*:
# - `$1`: Nameref to the frame variable (appended to)
__bu_tv_render_scrollbar()
{
    local -n __sbar_frame=$1
    __bu_tv_scrollbar_thumb
    local -r -i col=$((_TV_TABLE_COLS + 2))
    local -i i
    for (( i = 0; i < _TV_DATA_ROWS; i++ ))
    do
        if (( i >= _TV_SB_TOP && i < _TV_SB_TOP + _TV_SB_HEIGHT ))
        then
            __sbar_frame+=$'\e['$((i + 3))';'$col'H'$__BU_TV_SB_THUMB
        else
            __sbar_frame+=$'\e['$((i + 3))';'$col'H'$__BU_TV_SB_TRACK
        fi
    done
}

# *Description*:
# Join informational status parts with " | " and append the key hints that
# fit.  Hint words are dropped one at a time from the right, skipping the
# short set, so the leftmost hints last longest; if even the short set
# doesn't fit there are none.  Hints are never cut mid-word; only the
# informational text is ever truncated.  Hints before a __BU_TV_HINT_SEP
# word (the row actions) are drawn undimmed; the separator is dropped last,
# and only once no hint is left before it.
#
# *Params*:
# - `$1`: Full hint set (space-separated words)
# - `$2`: Short hint set (words of `$1` that are dropped last)
# - `$3...`: Informational parts
#
# *Returns*:
# - `_TV_STATUS`: Dimmed status line
# - `_TV_STATUS_HINTS`, `_TV_STATUS_HINTS_X`: the hints shown and their
#   first screen column, for clicks
__bu_tv_compose_status()
{
    local -r full=$1 short=$2
    shift 2
    local info= part
    for part in "$@"
    do
        if [[ -z "$info" ]]; then info=$part; else info+=" | $part"; fi
    done

    # Never write the bottom-right cell
    local -r -i room=$((_TV_TERM_COLS - 1))
    local -i avail=$room
    [[ -n "$info" ]] && avail=$((room - ${#info} - 3))

    local IFS=' '
    local -a words=()
    read -r -a words <<<"$full"
    local hints=$full
    local -i i=${#words[@]}
    while (( ${#hints} > avail && i > 0 ))
    do
        i=$((i - 1))
        [[ " $short $__BU_TV_HINT_SEP " == *" ${words[i]} "* ]] && continue
        unset 'words[i]'
        hints="${words[*]}"
    done
    hints=${hints#"$__BU_TV_HINT_SEP"}
    hints=${hints# }
    (( ${#hints} > avail )) && hints=

    local result=$info
    _TV_STATUS_HINTS=$hints
    _TV_STATUS_HINTS_X=1
    if [[ "$hints" == *" $__BU_TV_HINT_SEP "* ]]
    then
        hints=$__BU_TV_NORMAL_INTENSITY${hints%%" $__BU_TV_HINT_SEP "*}$__BU_TV_DIM" $__BU_TV_HINT_SEP "${hints#*" $__BU_TV_HINT_SEP "}
    fi
    if [[ -z "$info" ]]
    then
        result=$hints
    elif [[ -n "$hints" ]]
    then
        result+=" | $hints"
        _TV_STATUS_HINTS_X=$((${#info} + 4))
    elif (( ${#info} > room ))
    then
        result=${info:0:room}
    fi
    _TV_STATUS=$__BU_TV_DIM$result$__BU_TV_RESET
}

# *Description*:
# Build the search part of the status line: `/q k/n [col]` when the cursor
# is on the match last moved to, `/q n matches` otherwise, `/q no match`.
#
# *Returns*:
# - `_TV_SEARCH_STATUS`: Empty without a query
__bu_tv_search_status()
{
    _TV_SEARCH_STATUS=
    [[ -z "$_TV_SEARCH_QUERY" ]] && return 0
    local -r -i n=${#_TV_MATCHED_ROWS[@]}
    if (( n == 0 ))
    then
        _TV_SEARCH_STATUS="/$_TV_SEARCH_QUERY no match"
    elif (( _TV_MATCH_IDX >= 0 && _TV_MATCH_IDX < n )) \
        && (( _TV_MATCHED_ROWS[_TV_MATCH_IDX] == _TV_CUR_ROW ))
    then
        _TV_SEARCH_STATUS="/$_TV_SEARCH_QUERY $((_TV_MATCH_IDX + 1))/$n [${_TV_HEADERS[_TV_MATCHED_COLS[_TV_MATCH_IDX]]}]"
    elif (( n == 1 ))
    then
        _TV_SEARCH_STATUS="/$_TV_SEARCH_QUERY 1 match"
    else
        _TV_SEARCH_STATUS="/$_TV_SEARCH_QUERY $n matches"
    fi
    return 0
}

# *Description*:
# Build the table status line: `Row r/N | Col name (c/n)[ wide][ frozen]
# | K hidden | &filter v/N | Sorted: key ↑ | <search> | <hints>`, the
# middle parts only when they apply.  The hints start with the keys that
# undo or follow up the current state: + with hidden columns, n/N with
# search matches, Esc with a search or filter.
#
# *Returns*:
# - `_TV_STATUS`
__bu_tv_render_status()
{
    local -a parts=()
    [[ -n "$_TV_MESSAGE" ]] && parts+=("$_TV_MESSAGE")
    if (( _TV_NUM_VIEW > 0 ))
    then
        parts+=("Row $((_TV_CUR_ROW + 1))/$_TV_NUM_VIEW")
    else
        parts+=("No rows")
    fi

    if (( _TV_NUM_COLS > 0 ))
    then
        local col="Col ${_TV_HEADERS[_TV_CUR_COL]} ($((_TV_CUR_COL + 1))/$_TV_NUM_COLS)"
        [[ "${_TV_COL_EXPANDED[_TV_CUR_COL]:-false}" == true ]] && col+=' wide'
        (( _TV_CUR_COL < _TV_FROZEN_N )) && col+=' frozen'
        parts+=("$col")
    fi
    (( ${#_TV_HIDDEN[@]} )) && parts+=("${#_TV_HIDDEN[@]} hidden")
    [[ -n "$_TV_FILTER_QUERY" ]] && parts+=("&$_TV_FILTER_QUERY $_TV_NUM_VIEW/$_TV_NUM_ROWS")

    if [[ -n "$_TV_SORT_COL" ]]
    then
        local arrow='↑'
        [[ "$_TV_SORT_DIR" == desc ]] && arrow='↓'
        parts+=("Sorted: $_TV_SORT_COL $arrow")
    fi

    __bu_tv_search_status
    [[ -n "$_TV_SEARCH_STATUS" ]] && parts+=("$_TV_SEARCH_STATUS")

    # Row actions lead, set off from the built-in keys; of those, the keys
    # for the current state lead, so they outlast the general ones
    local hints= key
    for key in "${_TV_ACTION_KEYS[@]}"
    do
        hints+="$key:${_TV_ACTION_LABEL[$key]} "
    done
    [[ -n "$hints" ]] && hints+="$__BU_TV_HINT_SEP "
    (( ${#_TV_HIDDEN[@]} )) && hints+='+:unhide '
    (( ${#_TV_MATCHED_ROWS[@]} )) && hints+='n/N:match '
    [[ -n "$_TV_SEARCH_QUERY$_TV_FILTER_QUERY" ]] && hints+='Esc:clear '
    __bu_tv_preview_available && hints+='p:preview '
    __bu_tv_compose_status "$hints$__BU_TV_HINTS_TABLE" 'H:help' "${parts[@]}"
}

# *Description*:
# Full table frame: header, separator, data rows, sidebar, status line (or
# the search prompt), written with one printf.
__bu_tv_render_frame()
{
    # Screen layout:
    #   row 1          = header
    #   row 2          = separator
    #   rows 3..N-1    = data (TERM_ROWS - 3 rows)
    #   row N (bottom) = status line, or the search prompt while it is open
    #   right of table = scrollbar (a gap and the bar) on the data rows,
    #                    while the rows overflow them
    #   right edge     = column sidebar on rows 1..N-1, unless hidden
    #
    # Each row is drawn with absolute cursor positioning and \e[K
    # (clear-to-EOL) — no newlines anywhere, so the terminal can never
    # scroll and push the header off-screen.
    __bu_tv_data_rows
    local -r -i data_rows=$_TV_DATA_ROWS

    __bu_tv_query_prepare
    __bu_tv_compute_visible_cols

    local frame= line= attr

    __bu_tv_render_line -1 '' line
    frame+=$'\e[1;1H'$line$__BU_TV_CLEAR_LINE
    __bu_tv_render_line -2 '' line
    frame+=$'\e[2;1H'$line$__BU_TV_CLEAR_LINE
    # Without the sidebar, mark the columns scrolled off each side
    (( _TV_SIDEBAR_W == 0 )) && __bu_tv_render_col_markers frame

    local -i i row_idx
    for (( i = 0; i < data_rows; i++ ))
    do
        row_idx=$((_TV_ROW_OFFSET + i))
        if (( row_idx >= _TV_NUM_VIEW ))
        then
            frame+=$'\e['$((i + 3))$';1H'$__BU_TV_CLEAR_LINE
            continue
        fi
        attr=
        (( row_idx == _TV_CUR_ROW )) && attr=$__BU_TV_REVERSE
        __bu_tv_render_line "${_TV_VIEW[row_idx]}" "$attr" line
        frame+=$'\e['$((i + 3))$';1H'$line$__BU_TV_CLEAR_LINE
    done

    # Scrollbar and sidebar — drawn after the table rows so each row's \e[K
    # ran first
    if (( _TV_SCROLLBAR_W > 0 ))
    then
        __bu_tv_render_scrollbar frame
    fi
    if (( _TV_SIDEBAR_W > 0 ))
    then
        __bu_tv_render_sidebar frame "$data_rows"
    fi

    # Bottom row — absolute position, no trailing newline
    if "$_TV_PROMPT_ACTIVE"
    then
        # Clipped to its tail, leaving the last column for the cursor
        local ptext=$_TV_PROMPT_TEXT
        local -r -i maxw=$((_TV_TERM_COLS - 1))
        (( ${#ptext} > maxw )) && ptext=${ptext:${#ptext}-maxw}
        frame+=$'\e['$_TV_TERM_ROWS$';1H'$ptext$__BU_TV_CLEAR_LINE
        frame+=$'\e['$_TV_TERM_ROWS';'$((${#ptext} + 1))'H'$__BU_TV_CURSOR_SHOW
    else
        __bu_tv_render_status
        frame+=$'\e['$_TV_TERM_ROWS$';1H'$_TV_STATUS$__BU_TV_CLEAR_LINE$__BU_TV_CURSOR_HIDE
    fi

    printf '%s' "$frame"
}

# *Description*:
# Full overlay frame (record detail or help): a bold title, a separator,
# the overlay's lines from its scroll offset, and a status line.  Detail
# lines are pre-wrapped to the width; help lines are plain text, clipped.
__bu_tv_render_overlay()
{
    __bu_tv_data_rows
    local -r -i data_rows=$_TV_DATA_ROWS
    __bu_tv_overlay_clamp

    local title lines_var off_var full plain=false
    if [[ "$_TV_MODE" == help ]]
    then
        title=Keys
        lines_var=_TV_HELP_LINES
        off_var=_TV_HELP_OFFSET
        full=$__BU_TV_HINTS_HELP
        plain=true
    else
        title="Record $((_TV_CUR_ROW + 1))/$_TV_NUM_VIEW"
        lines_var=_TV_DETAIL_LINES
        off_var=_TV_DETAIL_OFFSET
        full=$__BU_TV_HINTS_DETAIL
    fi
    local -n __ov_lines=$lines_var __ov_off=$off_var
    local -r -i total=${#__ov_lines[@]}

    (( _TV_TERM_COLS > ${#__BU_TV_SPACES} )) && __bu_tv_ensure_pools $_TV_TERM_COLS
    local frame=$'\e[1;1H'$__BU_TV_BOLD$title$__BU_TV_RESET$__BU_TV_CLEAR_LINE
    frame+=$'\e[2;1H'${__BU_TV_DASHES:0:_TV_TERM_COLS}$__BU_TV_CLEAR_LINE

    local line
    local -i i idx
    for (( i = 0; i < data_rows; i++ ))
    do
        idx=$((__ov_off + i))
        line=
        if (( idx < total ))
        then
            line=${__ov_lines[idx]}
            "$plain" && line=${line:0:_TV_TERM_COLS}
        fi
        frame+=$'\e['$((i + 3))$';1H'$line$__BU_TV_CLEAR_LINE
    done

    local -a parts=()
    local -i last=$((__ov_off + data_rows))
    (( last > total )) && last=$total
    (( total > 0 )) && parts+=("Lines $((__ov_off + 1))-$last/$total")
    if [[ "$_TV_MODE" == detail ]]
    then
        __bu_tv_search_status
        [[ -n "$_TV_SEARCH_STATUS" ]] && parts+=("$_TV_SEARCH_STATUS")
    fi
    __bu_tv_compose_status "$full" 'q:back' "${parts[@]}"
    frame+=$'\e['$_TV_TERM_ROWS$';1H'$_TV_STATUS$__BU_TV_CLEAR_LINE$__BU_TV_CURSOR_HIDE

    printf '%s' "$frame"
}

# *Description*:
# Draw the screen for the current mode.  Called by the event loop and the
# search prompt.
__bu_tv_render()
{
    case "$_TV_MODE" in
    detail|help)
        __bu_tv_render_overlay
        ;;
    *)
        __bu_tv_render_frame
        ;;
    esac
}

# ═══════════════════════════════════════════════════════════════════════════
# Overlays
# ═══════════════════════════════════════════════════════════════════════════

# *Description*:
# Clamp both overlay scroll offsets to their content.
__bu_tv_overlay_clamp()
{
    __bu_tv_data_rows
    local -i max=$((${#_TV_DETAIL_LINES[@]} - _TV_DATA_ROWS))
    (( _TV_DETAIL_OFFSET > max )) && _TV_DETAIL_OFFSET=$max
    (( _TV_DETAIL_OFFSET < 0 )) && _TV_DETAIL_OFFSET=0
    max=$((${#_TV_HELP_LINES[@]} - _TV_DATA_ROWS))
    (( _TV_HELP_OFFSET > max )) && _TV_HELP_OFFSET=$max
    (( _TV_HELP_OFFSET < 0 )) && _TV_HELP_OFFSET=0
    return 0
}

# *Description*:
# Fetch the untruncated values of one record from its raw JSON in a single
# jq pass (the display cache is @tsv-escaped: nested JSON with quotes or
# backslashes would not parse back, and \n would show as two characters).
# Strings come out raw with real newlines, other types pretty-printed, null
# as __BU_TV_NULL; each value is followed by a U+0001 line.  Falls back to the
# cache text if the value count is off.
#
# *Params*:
# - `$1`: Row index
#
# *Returns*:
# - `_TV_DETAIL_VALUES`: One value per column
__bu_tv_detail_values()
{
    local -r -i row=$1
    _TV_DETAIL_VALUES=()
    local out=
    out=$("$BU_OUT_JQ" -r --args \
        '. as $r | $ARGS.positional[] as $k | ($r[$k] | if . == null then "\u0002" else . end), "\u0001"' \
        "${_TV_COLUMNS[@]}" <<<"${_TV_ROWS[row]}" 2>/dev/null) || out=
    # Every value is now terminated by "\n\x01\n"
    out+=$'\n'
    local -r term=$'\n\x01\n'
    while [[ "$out" == *"$term"* ]]
    do
        _TV_DETAIL_VALUES+=("${out%%"$term"*}")
        out=${out#*"$term"}
    done

    if (( ${#_TV_DETAIL_VALUES[@]} != _TV_NUM_COLS )) || [[ -n "$out" ]]
    then
        _TV_DETAIL_VALUES=()
        local -i j
        for (( j = 0; j < _TV_NUM_COLS; j++ ))
        do
            _TV_DETAIL_VALUES+=("${_TV_CELLS[row * _TV_NUM_COLS + j]:-}")
        done
    fi
    return 0
}

# *Description*:
# Word-wrap a line: break at the last space that fits, hard-break words
# longer than the width.  The space a line breaks at is dropped.
#
# *Params*:
# - `$1`: Text (no ANSI escapes, no newlines)
# - `$2`: Width
#
# *Returns*:
# - `_TV_SEGS`: (start length) pairs, at least one (an empty line is 0 0)
__bu_tv_wrap()
{
    local -r text=$1
    local -i -r width=$2 n=${#1}
    local -i pos=0
    local window head
    _TV_SEGS=()
    if (( n == 0 ))
    then
        _TV_SEGS=(0 0)
        return 0
    fi
    while (( pos < n ))
    do
        if (( n - pos <= width ))
        then
            _TV_SEGS+=("$pos" $((n - pos)))
            break
        fi
        if [[ "${text:pos+width:1}" == ' ' ]]
        then
            _TV_SEGS+=("$pos" "$width")
            pos=$((pos + width + 1))
            continue
        fi
        window=${text:pos:width}
        head=${window% *}
        if [[ "$head" != "$window" && -n "$head" ]]
        then
            _TV_SEGS+=("$pos" "${#head}")
            pos=$((pos + ${#head} + 1))
            continue
        fi
        _TV_SEGS+=("$pos" "$width")
        pos=$((pos + width))
    done
    return 0
}

# *Description*:
# Build the record-detail overlay for the cursor row: every column as
# `key  value`, keys padded to the longest header (the cursor column's key
# bold), values untruncated and word-wrapped to the terminal width with
# continuation lines indented under the value column, search hits
# highlighted.
#
# *Returns*:
# - `_TV_DETAIL_LINES`, `_TV_DETAIL_COL_LINE`
__bu_tv_build_detail()
{
    _TV_DETAIL_LINES=()
    _TV_DETAIL_COL_LINE=()
    (( _TV_NUM_VIEW == 0 || _TV_NUM_COLS == 0 )) && return 0
    __bu_tv_query_prepare
    __bu_tv_detail_values "${_TV_VIEW[_TV_CUR_ROW]}"

    local -i keyw=1 j s
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        (( ${#_TV_HEADERS[j]} > keyw )) && keyw=${#_TV_HEADERS[j]}
    done
    # Leave values at least half the width
    local -i max_key=$(((_TV_TERM_COLS - 2) / 2))
    (( max_key < 1 )) && max_key=1
    (( keyw > max_key )) && keyw=$max_key
    local -i valw=$((_TV_TERM_COLS - keyw - 2))
    (( valw < 1 )) && valw=1
    (( keyw + 2 > ${#__BU_TV_SPACES} )) && __bu_tv_ensure_pools $((keyw + 2))
    local -r indent=${__BU_TV_SPACES:0:keyw+2}

    local key lead value lline
    local -a llines=()
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        key=${_TV_HEADERS[j]}
        (( ${#key} > keyw )) && key="${key:0:keyw-1}…"
        if (( j == _TV_CUR_COL ))
        then
            lead=$__BU_TV_BOLD$key$__BU_TV_RESET
        else
            lead=$key
        fi
        lead+=${__BU_TV_SPACES:0:keyw-${#key}+2}
        _TV_DETAIL_COL_LINE[j]=${#_TV_DETAIL_LINES[@]}

        value=${_TV_DETAIL_VALUES[j]:-}
        if [[ "$value" == "$__BU_TV_NULL" ]]
        then
            _TV_DETAIL_LINES+=("$lead$__BU_TV_NULL_CELL")
            continue
        fi
        [[ $value == *$'\e'* ]] && __bu_tv_strip_ansi value
        value=${value//$'\t'/'    '}
        value=${value//$'\r'/}
        llines=()
        while :
        do
            llines+=("${value%%$'\n'*}")
            [[ $value == *$'\n'* ]] || break
            value=${value#*$'\n'}
        done

        for lline in "${llines[@]}"
        do
            __bu_tv_find_hits "$lline"
            __bu_tv_wrap "$lline" "$valw"
            for (( s = 0; s < ${#_TV_SEGS[@]}; s += 2 ))
            do
                __bu_tv_paint "$lline" "${_TV_SEGS[s]}" $((_TV_SEGS[s] + _TV_SEGS[s + 1])) "$__BU_TV_RESET"
                _TV_DETAIL_LINES+=("$lead$_TV_PAINT")
                lead=$indent
            done
        done
    done
    return 0
}

# *Description*:
# Scroll the detail overlay so the cursor column's first line is on screen.
__bu_tv_detail_show_col()
{
    __bu_tv_data_rows
    local -r -i line=${_TV_DETAIL_COL_LINE[_TV_CUR_COL]:-0}
    if (( line < _TV_DETAIL_OFFSET || line >= _TV_DETAIL_OFFSET + _TV_DATA_ROWS ))
    then
        _TV_DETAIL_OFFSET=$line
    fi
    __bu_tv_overlay_clamp
}

# *Description*:
# Open the record-detail overlay for the cursor row.
__bu_tv_open_detail()
{
    (( _TV_NUM_VIEW == 0 )) && return 0
    _TV_MODE=detail
    _TV_DETAIL_OFFSET=0
    __bu_tv_build_detail
    __bu_tv_detail_show_col
}

# *Description*:
# Open the help overlay; closing it returns to the current mode.
__bu_tv_open_help()
{
    _TV_HELP_RETURN=$_TV_MODE
    _TV_MODE=help
    _TV_HELP_OFFSET=0
}

# *Description*:
# Move the detail overlay to the next / previous record.
#
# *Params*:
# - `$1`: Row delta
__bu_tv_detail_record()
{
    local -r -i before=$_TV_CUR_ROW
    __bu_tv_move "$1" 0
    if (( _TV_CUR_ROW != before ))
    then
        __bu_tv_build_detail
        _TV_DETAIL_OFFSET=0
        __bu_tv_detail_show_col
    fi
}

# *Description*:
# Move the detail overlay to the next / previous search match.
#
# *Params*:
# - `$1`: forward or backward
__bu_tv_detail_match()
{
    __bu_tv_search_step "$1" || return 0
    __bu_tv_build_detail
    __bu_tv_detail_show_col
}

# ═══════════════════════════════════════════════════════════════════════════
# Search
# ═══════════════════════════════════════════════════════════════════════════

# *Description*:
# Recompute _TV_MATCHED_ROWS (view indices) and _TV_MATCHED_COLS (first
# matching column of each row) from the current query, over the rows the
# filter leaves in view.  Literal substring, smart case,
# matched on ANSI-stripped text.  Rows are prefiltered on their joined
# text; only matching rows are scanned cell by cell.  Never moves the
# cursor: sorting with an active query must keep it on its record.
__bu_tv_update_search_matches()
{
    _TV_MATCHED_ROWS=()
    _TV_MATCHED_COLS=()
    _TV_MATCH_IDX=-1
    __bu_tv_query_prepare
    local -r needle=$_TV_SEARCH_NEEDLE
    [[ -z "$needle" ]] && return 0

    local fold=false
    [[ "$_TV_SEARCH_FOLD" == true ]] && fold=true
    local -i v i j base
    local text
    for (( v = 0; v < _TV_NUM_VIEW; v++ ))
    do
        i=${_TV_VIEW[v]}
        text=${_TV_ROW_TEXT[i]:-}
        "$fold" && text=${text,,}
        [[ $text == *"$needle"* ]] || continue
        base=$((i * _TV_NUM_COLS))
        for (( j = 0; j < _TV_NUM_COLS; j++ ))
        do
            text=${_TV_CELLS[base + j]:-}
            [[ $text == *$'\e'* ]] && __bu_tv_strip_ansi text
            "$fold" && text=${text,,}
            if [[ $text == *"$needle"* ]]
            then
                _TV_MATCHED_ROWS+=("$v")
                _TV_MATCHED_COLS+=("$j")
                break
            fi
        done
    done
    return 0
}

# *Description*:
# Find the first match at/after (forward) or at/before (backward) a row,
# wrapping around.  The row may be out of range (cursor ± 1).
#
# *Params*:
# - `$1`: Row index
# - `$2`: forward or backward
#
# *Returns*:
# - `_TV_FOUND_IDX`: Index into _TV_MATCHED_ROWS
# - 1 if there are no matches
__bu_tv_search_from()
{
    local -r -i row=$1 n=${#_TV_MATCHED_ROWS[@]}
    local -r dir=$2
    _TV_FOUND_IDX=-1
    (( n == 0 )) && return 1

    # Binary search: lo = first index whose row is >= row
    local -i lo=0 hi=$n mid
    while (( lo < hi ))
    do
        mid=$(((lo + hi) / 2))
        if (( _TV_MATCHED_ROWS[mid] < row ))
        then
            lo=$((mid + 1))
        else
            hi=$mid
        fi
    done

    if [[ "$dir" == backward ]]
    then
        if (( lo < n && _TV_MATCHED_ROWS[lo] == row ))
        then
            _TV_FOUND_IDX=$lo
        else
            _TV_FOUND_IDX=$((lo - 1))
            (( _TV_FOUND_IDX < 0 )) && _TV_FOUND_IDX=$((n - 1))
        fi
    else
        _TV_FOUND_IDX=$lo
        (( lo >= n )) && _TV_FOUND_IDX=0
    fi
    return 0
}

# *Description*:
# Move the cursor row and column to a match; centre the row if it was off
# screen.
#
# *Params*:
# - `$1`: Index into _TV_MATCHED_ROWS
__bu_tv_goto_match()
{
    local -r -i idx=$1
    (( idx < 0 || idx >= ${#_TV_MATCHED_ROWS[@]} )) && return 0
    __bu_tv_data_rows
    local -r -i row=${_TV_MATCHED_ROWS[idx]}
    _TV_MATCH_IDX=$idx
    _TV_CUR_ROW=$row
    _TV_CUR_COL=${_TV_MATCHED_COLS[idx]}
    if (( row < _TV_ROW_OFFSET || row >= _TV_ROW_OFFSET + _TV_DATA_ROWS ))
    then
        _TV_ROW_OFFSET=$((row - _TV_DATA_ROWS / 2))
    fi
    __bu_tv_clamp_offsets
}

# *Description*:
# n / N: go to the next match after the cursor row, or the previous one
# before it (position-based, wrapping).
#
# *Params*:
# - `$1`: forward or backward
#
# *Returns*:
# - 1 if there are no matches
__bu_tv_search_step()
{
    local -i from=$((_TV_CUR_ROW + 1))
    [[ "$1" == backward ]] && from=$((_TV_CUR_ROW - 1))
    __bu_tv_search_from "$from" "$1" || return 1
    __bu_tv_goto_match "$_TV_FOUND_IDX"
    return 0
}

__bu_tv_search_clear()
{
    _TV_SEARCH_QUERY=
    _TV_SEARCH_NEEDLE=
    _TV_MATCHED_ROWS=()
    _TV_MATCHED_COLS=()
    _TV_MATCH_IDX=-1
}

# *Description*:
# Set the row filter and keep the cursor on its record (or the nearest row
# after it) at the same screen row; search matches follow the new view.
#
# *Params*:
# - `$1`: Filter (empty: every row)
# - `$2`: Data row of the cursor's record (-1: first row)
# - `$3`: Screen row of the cursor relative to the row offset
__bu_tv_filter_to()
{
    _TV_FILTER_QUERY=$1
    __bu_tv_apply_filter
    __bu_tv_place_record "$2" "$3"
    __bu_tv_update_search_matches
}

# *Description*:
# Incremental prompt on the status row, in raw mode, for search (/ ?) or
# the row filter (&).  Printable characters append, Backspace deletes,
# Ctrl-U clears, Esc cancels, Enter commits; every keystroke redraws.
#
# Search: every keystroke restores the pre-search cursor and offsets,
# re-clamps (the terminal may have been resized), re-runs the matcher and
# moves to the first match from the row the search began on.  An empty or
# cancelled query restores the previous query, cursor and offsets.
#
# Filter: starts from the current filter; every keystroke re-filters,
# keeping the cursor on its record.  What is shown is what Enter commits
# (an empty filter shows every row); Esc restores the previous filter.
#
# tty EOF cancels and quits (read_key reports EOF as a printable "q",
# which would otherwise be appended forever).
#
# *Params*:
# - `$1`: "/" (search forward), "?" (search backward) or "&" (filter)
__bu_tv_prompt()
{
    local -r pchar=$1
    local kind=search dir=forward
    case "$pchar" in
    '?') dir=backward ;;
    '&') kind=filter ;;
    esac
    local -r -i save_row=$_TV_CUR_ROW save_col=$_TV_CUR_COL \
        save_roff=$_TV_ROW_OFFSET save_coff=$_TV_COL_OFFSET save_idx=$_TV_MATCH_IDX
    __bu_tv_cursor_data
    local -r -i save_data=$_TV_FOUND_IDX
    local -r save_query=$_TV_SEARCH_QUERY save_filter=$_TV_FILTER_QUERY
    local buf= key commit=false redraw=true
    [[ "$kind" == filter ]] && buf=$save_filter

    _TV_PROMPT_ACTIVE=true
    _TV_PROMPT_TEXT=$pchar$buf
    while :
    do
        "$redraw" && __bu_tv_render
        redraw=true
        __bu_tv_read_key 1
        key=$_TV_KEY
        if "$_TV_EOF"
        then
            _TV_QUIT=true
            break
        fi
        case "$key" in
        none)
            # A trap fired (resize, suspend/resume, Ctrl-C)
            __bu_tv_process_signals
            "$_TV_QUIT" && break
            continue
            ;;
        $'\x0a')
            [[ -n "$buf" || "$kind" == filter ]] && commit=true
            break
            ;;
        escape|$'\e')
            break
            ;;
        $'\x7f'|$'\x08')
            buf=${buf%?}
            ;;
        $'\x15')
            buf=
            ;;
        *)
            # Named keys (up, page_down, mouse, ...) are words, not characters
            if (( ${#key} != 1 )) || [[ "$key" != [[:print:]] ]]
            then
                redraw=false
                continue
            fi
            buf+=$key
            ;;
        esac

        _TV_PROMPT_TEXT=$pchar$buf
        if [[ "$kind" == filter ]]
        then
            __bu_tv_filter_to "$buf" "$save_data" $((save_row - save_roff))
            _TV_CUR_COL=$save_col
            _TV_COL_OFFSET=$save_coff
            __bu_tv_clamp_offsets
            continue
        fi
        _TV_CUR_ROW=$save_row
        _TV_CUR_COL=$save_col
        _TV_ROW_OFFSET=$save_roff
        _TV_COL_OFFSET=$save_coff
        __bu_tv_clamp_offsets
        if [[ -z "$buf" ]]
        then
            _TV_SEARCH_QUERY=$save_query
            __bu_tv_update_search_matches
            _TV_MATCH_IDX=$save_idx
        else
            _TV_SEARCH_QUERY=$buf
            __bu_tv_update_search_matches
            if __bu_tv_search_from "$save_row" "$dir"
            then
                __bu_tv_goto_match "$_TV_FOUND_IDX"
            fi
        fi
    done
    _TV_PROMPT_ACTIVE=false
    _TV_PROMPT_TEXT=

    "$commit" && return 0
    if [[ "$kind" == filter ]]
    then
        __bu_tv_filter_to "$save_filter" "$save_data" $((save_row - save_roff))
    else
        _TV_SEARCH_QUERY=$save_query
        __bu_tv_update_search_matches
        _TV_CUR_ROW=$save_row
        _TV_ROW_OFFSET=$save_roff
    fi
    _TV_MATCH_IDX=$save_idx
    _TV_CUR_COL=$save_col
    _TV_COL_OFFSET=$save_coff
    __bu_tv_clamp_offsets
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Input handling
# ═══════════════════════════════════════════════════════════════════════════

# *Description*:
# Succeed if a trap has set a flag the event loop must act on.
__bu_tv_signal_pending()
{
    "$_TV_QUIT" || "$_TV_RESIZE_PENDING" || "$_TV_SUSPEND_PENDING" || "$_TV_RESUME_PENDING"
}

# *Description*:
# Read a single keypress into _TV_KEY.  Handles multi-byte escape sequences.
#
# Blocking mode reads in __BU_TV_KEY_POLL slices rather than one indefinite
# read: bash restarts a read interrupted by SIGWINCH and defers its trap
# until a byte arrives, so a resize would otherwise not redraw until the
# next keypress.  A slice that ends with no signal flag set just reads
# again, so an idle viewer never renders.
#
# *Params*:
# - `$1` (optional): 1 = block until a key arrives (default);
#                    0 = non-blocking probe (returns 1 if no input queued)
#
# *Returns*:
# - `_TV_KEY`: Key name (e.g. "up", "shift_right", "f1", "/", "q").
#   - real EOF (read rc=1)          -> "q" (quit), and _TV_EOF=true
#   - Enter (read rc=0, empty var)  -> $'\x0a' (read -n1 consumed the delimiter)
#   - CR (a tty left in raw mode)   -> $'\x0a'
#   - a trap set a signal flag or _TV_QUIT (read rc>128) -> "none"
#     (no-op; the event loop processes the flags, NOT quit by itself)
#   - an unrecognised escape sequence -> "none"
# - Exit 1 only in probe mode when no input was available.
__bu_tv_read_key()
{
    local -i blocking=${1:-1}
    local -i rc=0
    _TV_KEY=
    if (( blocking ))
    then
        while :
        do
            rc=0
            IFS= read -r -s -n 1 -t "$__BU_TV_KEY_POLL" _TV_KEY || rc=$?
            # rc>128: the slice timed out or a trapped signal interrupted it
            (( rc <= 128 )) && break
            __bu_tv_signal_pending && break
        done
    else
        # Probe with a hair of timeout so the byte (if any) is consumed
        IFS= read -r -s -n 1 -t 0.001 _TV_KEY || rc=$?
    fi

    if (( rc != 0 ))
    then
        if (( ! blocking ))
        then
            # Probe: nothing queued (timeout) or EOF — no key to dispatch
            return 1
        fi
        if (( rc > 128 ))
        then
            # A trap set a flag; the event loop processes it and redraws
            _TV_KEY=none
            return 0
        fi
        # Real EOF.  "q" is printable, so the prompt checks _TV_EOF instead
        _TV_EOF=true
        _TV_KEY=q
        return 0
    fi

    case "$_TV_KEY" in
    '')
        # rc=0 with an empty var: read -n1 consumed the newline delimiter
        _TV_KEY=$'\x0a'
        ;;
    $'\r')
        _TV_KEY=$'\x0a'
        ;;
    $'\x0c')
        _TV_KEY=ctrl_l
        ;;
    $'\e')
        __bu_tv_read_escape
        ;;
    esac
    return 0
}

# *Description*:
# Parse the rest of an escape sequence after ESC (each byte read with a
# short timeout; a lone ESC is the Escape key).
#
# *Returns*:
# - `_TV_KEY`
__bu_tv_read_escape()
{
    local seq=
    IFS= read -r -s -n 1 -t 0.01 seq
    if [[ -z "$seq" ]]
    then
        _TV_KEY=escape
        return 0
    fi

    if [[ "$seq" == '[' ]]
    then
        _TV_KEY=none
        IFS= read -r -s -n 1 -t 0.01 seq
        case "$seq" in
            '<') __bu_tv_read_mouse ;;
            A) _TV_KEY=up ;;
            B) _TV_KEY=down ;;
            C) _TV_KEY=right ;;
            D) _TV_KEY=left ;;
            H) _TV_KEY=home ;;
            F) _TV_KEY=end ;;
            1) IFS= read -r -s -n 1 -t 0.01 seq
               case "$seq" in
               '~') _TV_KEY=home ;;
               ';') __bu_tv_read_modified ;;
               [0-9])
                   # \e[1N~ function keys: F1 is \e[11~
                   local num=1$seq
                   IFS= read -r -s -n 1 -t 0.01 seq
                   [[ "$seq" == '~' && "$num" == 11 ]] && _TV_KEY=f1
                   ;;
               esac ;;
            2) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=insert ;;
            3) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=delete ;;
            4) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=end ;;
            5) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=page_up ;;
            6) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=page_down ;;
            7) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=home ;;
            8) IFS= read -r -s -n 1 -t 0.01 seq
               [[ "$seq" == '~' ]] && _TV_KEY=end ;;
        esac
    elif [[ "$seq" == 'O' ]]
    then
        _TV_KEY=none
        IFS= read -r -s -n 1 -t 0.01 seq
        case "$seq" in
            A) _TV_KEY=up ;;
            B) _TV_KEY=down ;;
            C) _TV_KEY=right ;;
            D) _TV_KEY=left ;;
            H) _TV_KEY=home ;;
            F) _TV_KEY=end ;;
            P) _TV_KEY=f1 ;;
        esac
    fi
    # Anything else (ESC + key): _TV_KEY stays ESC
    return 0
}

# *Description*:
# Decode an SGR mouse report after `\e[<`: `btn;x;y` then M (press, drag,
# wheel) or m (release), each byte read with the parser's short timeout and
# the body capped at 24 bytes.  Button bits: the low two are the button
# (0 left, 1 middle, 2 right), 4/8/16 are Shift/Alt/Ctrl (masked out), 32
# is motion with a button held, 64 is the wheel (64 up, 65 down).  A
# malformed report is the no-op key "none".
#
# *Returns*:
# - `_TV_KEY`: "mouse" (or "none")
# - `_TV_MOUSE_EVENT`, `_TV_MOUSE_BUTTON`, `_TV_MOUSE_X`, `_TV_MOUSE_Y`
#   (1-based screen coordinates)
__bu_tv_read_mouse()
{
    _TV_KEY=none
    local body= c=
    while (( ${#body} < 24 ))
    do
        c=
        IFS= read -r -s -n 1 -t 0.01 c
        [[ -z "$c" || "$c" == [Mm] ]] && break
        body+=$c
    done
    [[ "$c" == [Mm] ]] || return 0
    # A variable: a literal pattern with ";" is awkward inside [[ =~ ]]
    [[ "$body" =~ $__BU_TV_MOUSE_RE ]] || return 0

    local -i -r btn=$((10#${BASH_REMATCH[1]}))
    _TV_MOUSE_X=$((10#${BASH_REMATCH[2]}))
    _TV_MOUSE_Y=$((10#${BASH_REMATCH[3]}))
    _TV_MOUSE_BUTTON=$((btn & 3))
    if (( btn & 64 ))
    then
        case "$_TV_MOUSE_BUTTON" in
        0) _TV_MOUSE_EVENT=wheel_up ;;
        1) _TV_MOUSE_EVENT=wheel_down ;;
        *) return 0 ;;
        esac
    elif [[ "$c" == m ]]
    then
        _TV_MOUSE_EVENT=release
    elif (( btn & 32 ))
    then
        _TV_MOUSE_EVENT=drag
    else
        _TV_MOUSE_EVENT=press
    fi
    _TV_KEY=mouse
    return 0
}

# *Description*:
# Parse `<mod><final>` after `\e[1;`.  Modifier 2 (Shift), 5 (Ctrl) and 6
# (Ctrl+Shift) on an arrow give shift_<dir> (terminals and multiplexers
# differ in which modifier they pass through); any other modifier falls
# back to the plain arrow.  Home/End ignore the modifier.  The final byte
# is always consumed, so nothing is left to dispatch as a stray key.
#
# *Returns*:
# - `_TV_KEY`
__bu_tv_read_modified()
{
    local mod= fin= dir=
    IFS= read -r -s -n 1 -t 0.01 mod
    IFS= read -r -s -n 1 -t 0.01 fin
    # Two-digit modifiers (extended keyboard protocols)
    if [[ "$fin" == [0-9] ]]
    then
        mod+=$fin
        IFS= read -r -s -n 1 -t 0.01 fin
    fi
    case "$fin" in
    A) dir=up ;;
    B) dir=down ;;
    C) dir=right ;;
    D) dir=left ;;
    H) _TV_KEY=home; return 0 ;;
    F) _TV_KEY=end; return 0 ;;
    *) _TV_KEY=none; return 0 ;;
    esac
    case "$mod" in
    2|5|6) _TV_KEY=shift_$dir ;;
    *) _TV_KEY=$dir ;;
    esac
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Actions
# ═══════════════════════════════════════════════════════════════════════════

# ── Column order: freeze, hide, move ─────────────────────────────────────

# *Description*:
# Rearrange the columns: keys, labels and widen flags follow a list of
# current indices (an index left out is dropped), then the cache is rebuilt
# in the new order.  Restores the old order if the rebuild fails.
#
# *Params*:
# - `$@`: Current column indices, in their new order
__bu_tv_reorder_cols()
{
    local -a keys=() headers=() expanded=()
    local -a prev_keys=("${_TV_COLUMNS[@]}") prev_headers=("${_TV_HEADERS[@]}")
    local -a prev_expanded=()
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        prev_expanded+=("${_TV_COL_EXPANDED[j]:-false}")
    done
    for j in "$@"
    do
        keys+=("${prev_keys[j]}")
        headers+=("${prev_headers[j]}")
        expanded+=("${prev_expanded[j]}")
    done
    __bu_tv_set_cols keys headers expanded || {
        __bu_tv_set_cols prev_keys prev_headers prev_expanded || true
        return 1
    }
    return 0
}

# *Description*:
# Install a column list (keys, labels, widen flags) and rebuild the cache.
#
# *Params*:
# - `$1`, `$2`, `$3`: Names of the key, label and widen-flag arrays
__bu_tv_set_cols()
{
    local -n __sc_keys=$1 __sc_headers=$2 __sc_expanded=$3
    _TV_COLUMNS=("${__sc_keys[@]}")
    _TV_HEADERS=("${__sc_headers[@]}")
    _TV_COL_EXPANDED=("${__sc_expanded[@]}")
    _TV_NUM_COLS=${#_TV_COLUMNS[@]}
    __bu_tv_rebuild_cache || return 1
    __bu_tv_update_search_matches
    __bu_tv_clamp_offsets
    return 0
}

# *Description*:
# Move a column to another position.
#
# *Params*:
# - `$1`: Current index
# - `$2`: New index
__bu_tv_move_col()
{
    local -r -i from=$1 to=$2
    local -a order=()
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        (( j != from )) && order+=("$j")
    done
    order=("${order[@]:0:to}" "$from" "${order[@]:to}")
    __bu_tv_reorder_cols "${order[@]}"
}

# *Description*:
# < / >: move the cursor column one place left or right, within its block
# (frozen columns among themselves, scrolling ones among themselves).
#
# *Params*:
# - `$1`: -1 (left) or 1 (right)
__bu_tv_shift_col()
{
    (( _TV_NUM_COLS < 2 )) && return 0
    local -r -i j=$_TV_CUR_COL to=$((_TV_CUR_COL + $1))
    local -i lo=$_TV_FROZEN_N hi=$((_TV_NUM_COLS - 1))
    if (( j < _TV_FROZEN_N ))
    then
        lo=0
        hi=$((_TV_FROZEN_N - 1))
    fi
    (( to < lo || to > hi )) && return 0
    __bu_tv_move_col "$j" "$to" || return 0
    _TV_CUR_COL=$to
    __bu_tv_clamp_offsets
}

# *Description*:
# f: freeze the cursor column (it joins the frozen columns pinned at the
# left, which stay on screen while the rest scroll), or unfreeze it (it
# becomes the first scrolling column).  At least one column keeps
# scrolling.
__bu_tv_toggle_freeze()
{
    (( _TV_NUM_COLS < 2 )) && return 0
    local -r -i j=$_TV_CUR_COL k=$_TV_FROZEN_N
    if (( j < k ))
    then
        __bu_tv_move_col "$j" $((k - 1)) || return 0
        _TV_FROZEN_N=$((k - 1))
        _TV_CUR_COL=$((k - 1))
    else
        (( k + 1 >= _TV_NUM_COLS )) && return 0
        __bu_tv_move_col "$j" "$k" || return 0
        _TV_FROZEN_N=$((k + 1))
        _TV_CUR_COL=$k
    fi
    __bu_tv_clamp_offsets
}

# *Description*:
# -: hide the cursor column, or the given one (search and filter skip it
# too).  The last column can't be hidden.  + brings hidden columns back.
# The cursor stays on its column (on the next one when it was hidden).
#
# *Params*:
# - `$1` (optional): Column index (default: the cursor column)
__bu_tv_hide_col()
{
    (( _TV_NUM_COLS < 2 )) && return 0
    local -r -i j=${1:-$_TV_CUR_COL}
    local cur_key=
    (( j != _TV_CUR_COL )) && cur_key=${_TV_COLUMNS[_TV_CUR_COL]}
    local frozen=false
    (( j < _TV_FROZEN_N )) && frozen=true
    _TV_HIDDEN+=("$j"$'\x1f'"$frozen"$'\x1f'"${_TV_COLUMNS[j]}"$'\x1f'"${_TV_HEADERS[j]}"$'\x1f'"${_TV_COL_EXPANDED[j]:-false}")
    local -a order=()
    local -i i
    for (( i = 0; i < _TV_NUM_COLS; i++ ))
    do
        (( i != j )) && order+=("$i")
    done
    if ! __bu_tv_reorder_cols "${order[@]}"
    then
        unset '_TV_HIDDEN[-1]'
        return 0
    fi
    "$frozen" && _TV_FROZEN_N=$((_TV_FROZEN_N - 1))
    # At least one column keeps scrolling
    (( _TV_FROZEN_N > _TV_NUM_COLS - 1 )) && _TV_FROZEN_N=$((_TV_NUM_COLS - 1))
    [[ -n "$cur_key" ]] && __bu_tv_cursor_to_key "$cur_key"
    __bu_tv_clamp_offsets
}

# *Description*:
# Put the cursor on the column with the given key (unchanged if none has
# it).
#
# *Params*:
# - `$1`: Column key
__bu_tv_cursor_to_key()
{
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        if [[ "${_TV_COLUMNS[j]}" == "$1" ]]
        then
            _TV_CUR_COL=$j
            break
        fi
    done
    return 0
}

# *Description*:
# Bring one hidden column back (a click or drop on its sidebar entry) and
# put the cursor on it: by default at the index it was hidden from and
# frozen if it was, else where given.  The index is clamped into its block
# (frozen columns, or scrolling ones).  Columns hidden after it have their
# saved index shifted past it, so + still puts them back in place.
#
# *Params*:
# - `$1`: Hidden-stack index
# - `$2` (optional): Index to insert at
# - `$3` (optional): true to freeze it, false not to
__bu_tv_restore_col()
{
    local -r -i h=$1
    [[ -n "${_TV_HIDDEN[h]:-}" ]] || return 0
    local -a f=()
    IFS=$'\x1f' read -r -a f <<<"${_TV_HIDDEN[h]}"
    local -i at=${2:-${f[0]}}
    local -r frozen=${3:-${f[1]}}
    local -r -i k=$_TV_FROZEN_N
    if [[ "$frozen" == true ]]
    then
        (( at > k )) && at=$k
        (( at < 0 )) && at=0
    else
        (( at < k )) && at=$k
        (( at > _TV_NUM_COLS )) && at=$_TV_NUM_COLS
    fi

    local -a keys=("${_TV_COLUMNS[@]}") headers=("${_TV_HEADERS[@]}") expanded=()
    local -i j
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        expanded+=("${_TV_COL_EXPANDED[j]:-false}")
    done
    keys=("${keys[@]:0:at}" "${f[2]}" "${keys[@]:at}")
    headers=("${headers[@]:0:at}" "${f[3]}" "${headers[@]:at}")
    expanded=("${expanded[@]:0:at}" "${f[4]:-false}" "${expanded[@]:at}")
    __bu_tv_set_cols keys headers expanded || return 0
    [[ "$frozen" == true ]] && _TV_FROZEN_N=$((k + 1))

    local -a rest=()
    local -i g
    for (( g = 0; g < ${#_TV_HIDDEN[@]}; g++ ))
    do
        (( g == h )) && continue
        IFS=$'\x1f' read -r -a f <<<"${_TV_HIDDEN[g]}"
        if (( g > h && f[0] >= at ))
        then
            f[0]=$((f[0] + 1))
        fi
        rest+=("${f[0]}"$'\x1f'"${f[1]}"$'\x1f'"${f[2]}"$'\x1f'"${f[3]}"$'\x1f'"${f[4]:-false}")
    done
    _TV_HIDDEN=("${rest[@]}")
    _TV_CUR_COL=$at
    __bu_tv_clamp_offsets
}

# *Description*:
# +: bring every hidden column back, latest first, each at the index it
# was hidden from (so a run of hides undoes exactly).  The cursor stays on
# its column.
__bu_tv_restore_cols()
{
    (( ${#_TV_HIDDEN[@]} )) || return 0
    local -r cur_key=${_TV_COLUMNS[_TV_CUR_COL]:-}
    local -a keys=("${_TV_COLUMNS[@]}") headers=("${_TV_HEADERS[@]}") expanded=()
    local -i j h at frozen_n=$_TV_FROZEN_N
    for (( j = 0; j < _TV_NUM_COLS; j++ ))
    do
        expanded+=("${_TV_COL_EXPANDED[j]:-false}")
    done
    local -a f=()
    for (( h = ${#_TV_HIDDEN[@]} - 1; h >= 0; h-- ))
    do
        IFS=$'\x1f' read -r -a f <<<"${_TV_HIDDEN[h]}"
        at=${f[0]}
        (( at > ${#keys[@]} )) && at=${#keys[@]}
        keys=("${keys[@]:0:at}" "${f[2]}" "${keys[@]:at}")
        headers=("${headers[@]:0:at}" "${f[3]}" "${headers[@]:at}")
        expanded=("${expanded[@]:0:at}" "${f[4]:-false}" "${expanded[@]:at}")
        [[ "${f[1]}" == true ]] && frozen_n=$((frozen_n + 1))
    done
    __bu_tv_set_cols keys headers expanded || return 0
    _TV_HIDDEN=()
    _TV_FROZEN_N=$frozen_n
    __bu_tv_cursor_to_key "$cur_key"
    __bu_tv_clamp_offsets
}

# ── Mouse ────────────────────────────────────────────────────────────────

# *Description*:
# Current time in milliseconds: EPOCHREALTIME when available, else
# `date +%s%N` when it prints digits (GNU), else whole seconds.
#
# *Returns*:
# - `_TV_NOW_MS`
__bu_tv_now_ms()
{
    local t=
    if [[ -n "${EPOCHREALTIME:-}" ]]
    then
        t=${EPOCHREALTIME//[.,]/}
        _TV_NOW_MS=$((10#$t / 1000))
        return 0
    fi
    t=$(date +%s%N 2>/dev/null) || t=
    if [[ "$t" =~ ^[0-9]+$ ]]
    then
        _TV_NOW_MS=$((10#$t / 1000000))
    else
        printf -v t '%(%s)T' -1
        _TV_NOW_MS=$((10#$t * 1000))
    fi
    return 0
}

# *Description*:
# m: toggle mouse reporting.  The terminal's own click-drag text selection
# only works while it is off.
__bu_tv_toggle_mouse()
{
    if "$_TV_MOUSE"
    then
        _TV_MOUSE=false
        printf '%s' "$__BU_TV_MOUSE_OFF"
    else
        _TV_MOUSE=true
        printf '%s' "$__BU_TV_MOUSE_ON"
    fi
    _TV_SB_GRABBED=false
    _TV_SIDEBAR_DRAG=
    return 0
}

# *Description*:
# Column under a screen x in the last frame's visible columns.  The gap
# after a column counts as that column.
#
# *Params*:
# - `$1`: 1-based screen column
#
# *Returns*:
# - `_TV_FOUND_IDX`: Column index, or -1 right of the last visible column
__bu_tv_col_at()
{
    local -r -i x=$1
    local -i p=1 j
    _TV_FOUND_IDX=-1
    for j in "${_TV_VIS_COLS[@]}"
    do
        p=$((p + _TV_COL_WIDTHS[j] + 2))
        if (( x < p ))
        then
            _TV_FOUND_IDX=$j
            break
        fi
    done
    return 0
}

# *Description*:
# Left press in the column sidebar, hit-tested against the rows the last
# frame drew.  On the cursor column's entry, ⇤ (and the cell before it)
# freezes / unfreezes it and × (and the cell before it) hides it.  Any
# other column entry selects its column (the clamp scrolls the viewport by
# the minimum); column and hidden entries can then be dragged (see
# __bu_tv_sidebar_release).  "↑ N more" / "↓ N more" select the column
# just past them, or scroll the list one row when that row isn't a column.
#
# *Params*:
# - `$1`: 1-based screen column
# - `$2`: 1-based screen row
__bu_tv_sidebar_press()
{
    local -r -i x=$1 i=$(($2 - 3))
    (( i < 0 || i >= ${#_TV_SIDEBAR_ROW_IDX[@]} )) && return 0
    local -r -i li=${_TV_SIDEBAR_ROW_IDX[i]}
    local -i next
    if (( li == -1 || li == -2 ))
    then
        next=$((_TV_SIDEBAR_START - 1))
        (( li == -2 )) && next=$_TV_SIDEBAR_END
        if [[ "${_TV_SIDEBAR_LIST_KIND[next]:-}" == col ]]
        then
            _TV_SIDEBAR_SCROLL=-1
            _TV_CUR_COL=${_TV_SIDEBAR_LIST_ARG[next]}
            __bu_tv_clamp_offsets
        elif (( li == -1 ))
        then
            _TV_SIDEBAR_SCROLL=$((_TV_SIDEBAR_START - 1))
        else
            _TV_SIDEBAR_SCROLL=$((_TV_SIDEBAR_START + 1))
        fi
        return 0
    fi
    (( li < 0 )) && return 0

    local -r -i arg=${_TV_SIDEBAR_LIST_ARG[li]}
    # First cell of the cursor entry's " ⇤ ×"
    local -r -i btn=$((_TV_TABLE_COLS + _TV_SCROLLBAR_W + 1 + _TV_SIDEBAR_NAME_W + 1))
    case "${_TV_SIDEBAR_LIST_KIND[li]}" in
    col)
        if (( arg == _TV_CUR_COL && x >= btn ))
        then
            if (( x <= btn + 1 ))
            then
                __bu_tv_toggle_freeze
            else
                __bu_tv_hide_col
            fi
            return 0
        fi
        _TV_SIDEBAR_DRAG=col
        _TV_SIDEBAR_DRAG_ID=${_TV_COLUMNS[arg]}
        _TV_CUR_COL=$arg
        __bu_tv_clamp_offsets
        ;;
    hid)
        _TV_SIDEBAR_DRAG=hid
        _TV_SIDEBAR_DRAG_ID=$arg
        ;;
    *)
        return 0
        ;;
    esac
    _TV_SIDEBAR_DRAG_ROW=$i
    _TV_SIDEBAR_DROP_ROW=-99
    return 0
}

# *Description*:
# Drag of a pressed sidebar entry: once the pointer leaves the entry's row
# it tracks the row under it (drawn underlined as the drop target).
__bu_tv_sidebar_drag()
{
    local -r -i row=$((_TV_MOUSE_Y - 3))
    (( row != _TV_SIDEBAR_DRAG_ROW || _TV_SIDEBAR_DROP_ROW != -99 )) \
        && _TV_SIDEBAR_DROP_ROW=$row
    return 0
}

# *Description*:
# Release after a sidebar press.  Without a drag, a hidden entry comes
# back (__bu_tv_restore_col); a column entry was already selected by the
# press.  After a drag, the entry is dropped on the row released over
# (__bu_tv_sidebar_drop).
__bu_tv_sidebar_release()
{
    [[ -n "$_TV_SIDEBAR_DRAG" ]] || return 0
    local -r kind=$_TV_SIDEBAR_DRAG id=$_TV_SIDEBAR_DRAG_ID
    local -r -i dropped=$((_TV_SIDEBAR_DROP_ROW != -99))
    _TV_SIDEBAR_DRAG=
    _TV_SIDEBAR_DROP_ROW=-99
    if (( dropped ))
    then
        __bu_tv_sidebar_drop "$kind" "$id" $((_TV_MOUSE_Y - 3))
    elif [[ "$kind" == hid ]]
    then
        __bu_tv_restore_col "$id"
    fi
    return 0
}

# *Description*:
# Drop a dragged sidebar entry on a data row (as the last frame drew it).
# The row picks a block and a place in it: a frozen column's row, or the
# title rows above the list (first place), freeze there; a scrolling
# column's row moves there; the divider is the border, so it unfreezes a
# frozen column (first scrolling place) and freezes any other (last
# frozen place); the Hidden title, a hidden entry or the blank rows below
# hide.  A column takes the dropped-on row's place; a hidden column comes
# back there.  "N more" rows do nothing, and at least one column keeps
# scrolling.  The cursor follows the column.
#
# *Params*:
# - `$1`: col or hid
# - `$2`: Column key (col) or hidden-stack index (hid)
# - `$3`: Data row (< 0 for the title rows)
__bu_tv_sidebar_drop()
{
    local -r kind=$1 id=$2
    local -r -i row=$3 k=$_TV_FROZEN_N n=$_TV_NUM_COLS
    local -i src=-1 j li=-3 pos=0
    if [[ "$kind" == col ]]
    then
        for (( j = 0; j < n; j++ ))
        do
            [[ "${_TV_COLUMNS[j]}" == "$id" ]] && src=$j && break
        done
        (( src < 0 )) && return 0
    fi

    # Target block (frozen, scroll or hide) and place in it
    local zone=
    if (( row < 0 ))
    then
        zone=frozen
    else
        (( row < ${#_TV_SIDEBAR_ROW_IDX[@]} )) && li=${_TV_SIDEBAR_ROW_IDX[row]}
        if (( li == -3 ))
        then
            zone=hide
        elif (( li < 0 ))
        then
            return 0
        else
            case "${_TV_SIDEBAR_LIST_KIND[li]}" in
            col)
                pos=${_TV_SIDEBAR_LIST_ARG[li]}
                if (( pos < k ))
                then
                    zone=frozen
                else
                    zone=scroll
                    pos=$((pos - k))
                fi
                ;;
            div)
                if (( src >= 0 && src < k ))
                then
                    zone=scroll
                else
                    zone=frozen
                    pos=$k
                fi
                ;;
            *)
                zone=hide
                ;;
            esac
        fi
    fi

    if [[ "$kind" == hid ]]
    then
        case "$zone" in
        frozen) __bu_tv_restore_col "$id" "$pos" true ;;
        scroll) __bu_tv_restore_col "$id" $((k + pos)) false ;;
        esac
        return 0
    fi

    local -i to
    case "$zone" in
    hide)
        __bu_tv_hide_col "$src"
        return 0
        ;;
    frozen)
        if (( src < k ))
        then
            to=$pos
            (( to > k - 1 )) && to=$((k - 1))
            __bu_tv_move_col "$src" "$to" || return 0
        else
            (( k + 1 >= n )) && return 0
            __bu_tv_move_col "$src" "$pos" || return 0
            _TV_FROZEN_N=$((k + 1))
        fi
        ;;
    scroll)
        if (( src < k ))
        then
            to=$((k - 1 + pos))
            (( to > n - 1 )) && to=$((n - 1))
            __bu_tv_move_col "$src" "$to" || return 0
            _TV_FROZEN_N=$((k - 1))
        else
            to=$((k + pos))
            (( to > n - 1 )) && to=$((n - 1))
            __bu_tv_move_col "$src" "$to" || return 0
        fi
        ;;
    esac
    __bu_tv_cursor_to_key "$id"
    __bu_tv_clamp_offsets
}

# *Description*:
# Key of the status-line hint under a screen column, as last drawn: the
# key before the ":" ("Enter" and "Esc" by name), for "a/b" pairs the one
# clicked (a when the label is).
#
# *Params*:
# - `$1`: 1-based screen column
#
# *Returns*:
# - `_TV_KEY`: The key, or "none" off the hints
__bu_tv_status_hint_key()
{
    _TV_KEY=none
    local -r hints=$_TV_STATUS_HINTS
    local -r -i p=$(($1 - _TV_STATUS_HINTS_X))
    (( p < 0 || p >= ${#hints} )) && return 0
    [[ "${hints:p:1}" == ' ' ]] && return 0
    local pre=${hints:0:p} rest=${hints:p}
    pre=${pre##* }
    local -r word=$pre${rest%% *}
    [[ "$word" == ?*:* ]] || return 0
    local -r keys=${word%%:*}
    local -i off=${#pre}
    (( off > ${#keys} )) && off=0
    local key=$keys
    if [[ "$keys" == ?*/?* ]]
    then
        key=${keys%%/*}
        (( off > ${#key} )) && key=${keys#*/}
    fi
    case "$key" in
    Enter) key=$'\x0a' ;;
    Esc)   key=escape ;;
    esac
    _TV_KEY=$key
    return 0
}

# *Description*:
# Left press on the scrollbar: above the thumb pages up, below pages down,
# on it grabs the thumb (remembering the pointer's distance from its top).
#
# *Params*:
# - `$1`: 1-based screen row
__bu_tv_scrollbar_press()
{
    local -r -i r=$(($1 - 3))
    __bu_tv_scrollbar_thumb
    (( r < 0 || r >= _TV_DATA_ROWS )) && return 0
    if (( r < _TV_SB_TOP ))
    then
        __bu_tv_page_rows "-$_TV_DATA_ROWS"
    elif (( r >= _TV_SB_TOP + _TV_SB_HEIGHT ))
    then
        __bu_tv_page_rows "$_TV_DATA_ROWS"
    else
        _TV_SB_GRABBED=true
        _TV_SB_GRAB_DY=$((r - _TV_SB_TOP))
    fi
    return 0
}

# *Description*:
# Drag of the grabbed thumb: its top follows the pointer (clamped to the
# track) and the row offset is the inverse of the thumb mapping.
__bu_tv_scrollbar_drag()
{
    __bu_tv_scrollbar_thumb
    (( _TV_SB_ROOM < 1 )) && return 0
    local -i top=$((_TV_MOUSE_Y - 3 - _TV_SB_GRAB_DY))
    (( top < 0 )) && top=0
    (( top > _TV_SB_ROOM )) && top=$_TV_SB_ROOM
    __bu_tv_scroll_to $(((top * _TV_SB_MAX_OFF + _TV_SB_ROOM / 2) / _TV_SB_ROOM))
}

# *Description*:
# Left press in table mode, by screen region: a status-line hint presses
# its key; sidebar and scrollbar as above; header or separator selects the column under x;
# a data cell moves the cursor there (right of the last visible column the
# cursor column stays), and a second press on the same row within
# __BU_TV_DOUBLE_CLICK_MS opens the record-detail overlay.
__bu_tv_mouse_press()
{
    local -r -i x=$_TV_MOUSE_X y=$_TV_MOUSE_Y
    _TV_SIDEBAR_DRAG=
    if (( y == _TV_TERM_ROWS ))
    then
        __bu_tv_status_hint_key "$x"
        [[ "$_TV_KEY" != none ]] && __bu_tv_dispatch_key
        return 0
    fi
    (( y > _TV_TERM_ROWS || y < 1 )) && return 0
    if (( _TV_SIDEBAR_W > 0 && x > _TV_TABLE_COLS + _TV_SCROLLBAR_W ))
    then
        __bu_tv_sidebar_press "$x" "$y"
        return 0
    fi
    if (( _TV_SCROLLBAR_W > 0 && x == _TV_TABLE_COLS + 2 ))
    then
        __bu_tv_scrollbar_press "$y"
        return 0
    fi

    __bu_tv_col_at "$x"
    if (( y <= 2 ))
    then
        if (( _TV_FOUND_IDX >= 0 ))
        then
            _TV_CUR_COL=$_TV_FOUND_IDX
            __bu_tv_clamp_offsets
        fi
        return 0
    fi

    local -r -i row=$((_TV_ROW_OFFSET + y - 3))
    (( row >= _TV_NUM_VIEW )) && return 0
    _TV_CUR_ROW=$row
    (( _TV_FOUND_IDX >= 0 )) && _TV_CUR_COL=$_TV_FOUND_IDX
    __bu_tv_clamp_offsets

    __bu_tv_now_ms
    if (( row == _TV_CLICK_ROW && _TV_NOW_MS - _TV_CLICK_MS <= __BU_TV_DOUBLE_CLICK_MS ))
    then
        _TV_CLICK_ROW=-1
        __bu_tv_open_detail
    else
        _TV_CLICK_ROW=$row
        _TV_CLICK_MS=$_TV_NOW_MS
    fi
    return 0
}

# *Description*:
# A mouse event (key "mouse") in table mode: the wheel scrolls three rows
# (offset-driven), or the sidebar list over a sidebar taller than the
# screen; a left press acts by region; drags move a grabbed scrollbar
# thumb or a pressed sidebar entry; a release ends the grab or drops the
# entry.  Other buttons are ignored.
__bu_tv_mouse_table()
{
    local -i step=3
    case "$_TV_MOUSE_EVENT" in
    wheel_up|wheel_down)
        [[ "$_TV_MOUSE_EVENT" == wheel_up ]] && step=-3
        if (( _TV_SIDEBAR_W > 0 && _TV_MOUSE_X > _TV_TABLE_COLS + _TV_SCROLLBAR_W
            && _TV_SIDEBAR_NROWS > _TV_DATA_ROWS ))
        then
            _TV_SIDEBAR_SCROLL=$((_TV_SIDEBAR_START + step))
            (( _TV_SIDEBAR_SCROLL < 0 )) && _TV_SIDEBAR_SCROLL=0
        else
            __bu_tv_scroll_to $((_TV_ROW_OFFSET + step))
        fi
        ;;
    release)
        _TV_SB_GRABBED=false
        __bu_tv_sidebar_release
        ;;
    drag)
        if "$_TV_SB_GRABBED"
        then
            __bu_tv_scrollbar_drag
        elif [[ -n "$_TV_SIDEBAR_DRAG" ]]
        then
            __bu_tv_sidebar_drag
        fi
        ;;
    press)      (( _TV_MOUSE_BUTTON == 0 )) && __bu_tv_mouse_press ;;
    esac
    return 0
}

# ── Sort ─────────────────────────────────────────────────────────────────

# *Description*:
# Sort rows by the given column key.  Toggles direction if already sorted
# by this column, unless a direction is given.  The previous sort state is
# kept if the sort fails, so the status never shows an unapplied sort.
#
# *Params*:
# - `$1`: Column key
# - `$2` (optional): Force direction ("asc" or "desc")
__bu_tv_sort_by_column()
{
    local col_key=$1
    local force_dir=${2:-}
    [[ -z "$col_key" ]] && return 0

    local -r prev_col=$_TV_SORT_COL prev_dir=$_TV_SORT_DIR
    if [[ -n "$force_dir" ]]
    then
        _TV_SORT_DIR=$force_dir
    elif [[ "$_TV_SORT_COL" == "$col_key" && "$_TV_SORT_DIR" == asc ]]
    then
        _TV_SORT_DIR=desc
    else
        _TV_SORT_DIR=asc
    fi
    _TV_SORT_COL=$col_key

    if ! __bu_tv_apply_sort
    then
        _TV_SORT_COL=$prev_col
        _TV_SORT_DIR=$prev_dir
        return 1
    fi
    return 0
}

# *Description*:
# Sort by the cursor column (s / S).
#
# *Params*:
# - `$1` (optional): Force direction
__bu_tv_sort_cursor_col()
{
    (( _TV_NUM_COLS == 0 )) && return 0
    __bu_tv_sort_by_column "${_TV_COLUMNS[_TV_CUR_COL]}" "${1:-}" || true
}

# *Description*:
# Apply current sort to _TV_ROWS via jq and rebuild the cache.  Sorting raw
# values (not cell strings) orders numbers numerically and null first.
# jq emits the permutation of original indices first, so the cursor
# follows its record (keeping its screen position where possible); the
# cache rebuild re-applies the row filter in the new order.
#
# *Returns*:
# - `_TV_SORT_PERM`: New-to-old row index permutation
# - 1 with rows untouched if jq's output is not one permutation line plus
#   one line per row; 1 with rows, cursor and offsets restored (and the
#   old cache rebuilt) if the cache rebuild fails.
__bu_tv_apply_sort()
{
    [[ -z "$_TV_SORT_COL" ]] && return 0

    local jq_expr='to_entries | sort_by(.value[$k])'
    [[ "$_TV_SORT_DIR" == desc ]] && jq_expr+=' | reverse'
    jq_expr+=' | (map(.key) | @tsv), (.[].value | tojson)'

    local -a sorted=()
    mapfile -t sorted < <(printf '%s\n' "${_TV_ROWS[@]}" \
        | "$BU_OUT_JQ" -r -s --arg k "$_TV_SORT_COL" "$jq_expr")
    if (( ${#sorted[@]} != _TV_NUM_ROWS + 1 ))
    then
        bu_log_err "bu view-table: sort by $_TV_SORT_COL produced ${#sorted[@]} lines, expected $((_TV_NUM_ROWS + 1)); rows left unsorted"
        return 1
    fi

    local -a prev_rows=("${_TV_ROWS[@]}")
    local -r -i prev_cur=$_TV_CUR_ROW prev_roff=$_TV_ROW_OFFSET
    __bu_tv_cursor_data
    local -r -i prev_data=$_TV_FOUND_IDX
    _TV_ROWS=("${sorted[@]:1}")
    if ! __bu_tv_rebuild_cache
    then
        _TV_ROWS=("${prev_rows[@]}")
        __bu_tv_rebuild_cache || true
        _TV_CUR_ROW=$prev_cur
        _TV_ROW_OFFSET=$prev_roff
        __bu_tv_update_search_matches
        __bu_tv_clamp_offsets
        return 1
    fi
    IFS=$'\t' read -r -a _TV_SORT_PERM <<<"${sorted[0]}"

    # The cursor's record moved from data row prev_data to new_data; the
    # rebuild re-applied the filter in the new order
    local -i i new_data=-1
    for (( i = 0; i < _TV_NUM_ROWS; i++ ))
    do
        if (( _TV_SORT_PERM[i] == prev_data ))
        then
            new_data=$i
            break
        fi
    done
    __bu_tv_place_record "$new_data" $((prev_cur - prev_roff))
    __bu_tv_update_search_matches
    return 0
}

# ── Row actions ──────────────────────────────────────────────────────────

# *Description*:
# Bind a row action: KEY runs COMMAND, eval'd in the viewer's own shell (so
# what it changes stays visible to later actions and to --reload) with the
# cursor record (JSON) in BU_TV_RECORD, exported. Its stdout and stderr are
# captured; the last non-empty line shows on the status line ("failed: ..."
# when it returns non-zero). q, Q and H cannot be rebound.
#
# *Params*:
# - `$1`: Key (one printable character)
# - `$2`: Label for the status-line hint and the help
# - `$3`: Command
#
# *Returns*:
# - 1 (with an error logged) for an invalid or reserved key
bu_tv_set_action()
{
    local -r key=$1 label=$2 cmd=$3
    if (( ${#key} != 1 )) || [[ "$key" != [[:graph:]] ]]
    then
        bu_log_err "bu view-table: an action key must be one printable character, got [$key]"
        return 1
    fi
    case "$key" in
    q|Q|H)
        bu_log_err "bu view-table: $key cannot be bound to an action"
        return 1
        ;;
    esac
    [[ -v "_TV_ACTION_CMD[$key]" ]] || _TV_ACTION_KEYS+=("$key")
    _TV_ACTION_CMD[$key]=$cmd
    _TV_ACTION_LABEL[$key]=${label:-action}
    __bu_tv_build_help
    return 0
}

# Rebuild the help overlay: the row actions, which the program showing the
# table added, then the built-in keys
__bu_tv_build_help()
{
    _TV_HELP_LINES=("${__BU_TV_HELP_LINES[@]}")
    (( ${#_TV_ACTION_KEYS[@]} )) || return 0
    _TV_HELP_LINES=('Actions (added by the program showing this table)')
    local key
    for key in "${_TV_ACTION_KEYS[@]}"
    do
        _TV_HELP_LINES+=("  $(printf '%-19s' "$key")${_TV_ACTION_LABEL[$key]}")
    done
    _TV_HELP_LINES+=('' 'Built-in keys' '' "${__BU_TV_HELP_LINES[@]}")
    return 0
}

# *Description*:
# Run the row action bound to KEY on the cursor record, then reload the rows
# if a reload command is set.
#
# *Params*:
# - `$1`: Action key
__bu_tv_run_action()
{
    local -r key=$1
    __bu_tv_cursor_data
    if (( _TV_FOUND_IDX < 0 ))
    then
        _TV_MESSAGE="No row for ${_TV_ACTION_LABEL[$key]}"
        return 0
    fi
    local -r record=${_TV_ROWS[_TV_FOUND_IDX]}
    local key_value=
    if [[ -n "$_TV_KEY_COL" ]]
    then
        key_value=$("$BU_OUT_JQ" -r --arg k "$_TV_KEY_COL" '.[$k] // empty | tostring' <<<"$record" 2>/dev/null)
    fi
    [[ -n "$_TV_ACTION_OUT" ]] || _TV_ACTION_OUT=${BU_TMP_DIR:-/tmp}/tv-action.$$
    local -i rc=0
    __bu_tv_eval_action "${_TV_ACTION_CMD[$key]}" "$record" >"$_TV_ACTION_OUT" 2>&1 || rc=$?

    # The last non-empty output line is the message
    local -a out=()
    local line message=
    mapfile -t out < "$_TV_ACTION_OUT" 2>/dev/null
    local -i i
    for (( i = ${#out[@]} - 1; i >= 0; i-- ))
    do
        line=${out[i]}
        __bu_tv_strip_ansi line
        if [[ -n "${line//[[:space:]]/}" ]]
        then
            message=$line
            break
        fi
    done
    (( rc != 0 )) && message="failed: ${message:-${_TV_ACTION_LABEL[$key]} returned $rc}"
    [[ -n "$_TV_RELOAD_CMD" ]] && __bu_tv_reload "$_TV_FOUND_IDX" "$key_value"
    _TV_MESSAGE=$message
    return 0
}

# Eval an action command with the record exported as BU_TV_RECORD
__bu_tv_eval_action()
{
    local -x BU_TV_RECORD=$2
    eval "$1"
}

# *Description*:
# Replace the rows with the reload command's JSONL output (run in the
# viewer's shell, after the action), keep the sort, filter and columns, and
# put the cursor back on its record: the row whose key column has the same
# value, else the same data row (clamped).
#
# *Params*:
# - `$1`: Data row of the cursor before the action
# - `$2`: Its key column value (empty: none)
__bu_tv_reload()
{
    local -r -i prev_data=$1
    local -r key_value=$2
    local -r -i rel=$((_TV_CUR_ROW - _TV_ROW_OFFSET))
    local -a lines=() rows=()
    mapfile -t lines < <(eval "$_TV_RELOAD_CMD" 2>>"$_TV_ACTION_OUT")
    local line
    for line in "${lines[@]}"
    do
        [[ -n "$line" ]] && rows+=("$line")
    done

    local -a prev_rows=("${_TV_ROWS[@]}")
    local -r -i prev_n=$_TV_NUM_ROWS
    _TV_ROWS=("${rows[@]}")
    _TV_NUM_ROWS=${#rows[@]}
    if ! __bu_tv_rebuild_cache
    then
        _TV_ROWS=("${prev_rows[@]}")
        _TV_NUM_ROWS=$prev_n
        __bu_tv_rebuild_cache || true
        _TV_MESSAGE="reload failed"
        return 0
    fi
    __bu_tv_apply_sort || true

    local -i target=$prev_data
    if [[ -n "$key_value" && -n "$_TV_KEY_COL" ]] && (( _TV_NUM_ROWS > 0 ))
    then
        local -a keys=()
        mapfile -t keys < <(printf '%s\n' "${_TV_ROWS[@]}" \
            | "$BU_OUT_JQ" -r --arg k "$_TV_KEY_COL" '.[$k] // "" | tostring' 2>/dev/null)
        local -i i
        for (( i = 0; i < ${#keys[@]}; i++ ))
        do
            if [[ "${keys[i]}" == "$key_value" ]]
            then
                target=$i
                break
            fi
        done
    fi
    (( target >= _TV_NUM_ROWS )) && target=$((_TV_NUM_ROWS - 1))
    __bu_tv_compute_widths
    __bu_tv_place_record "$target" "$rel"
    __bu_tv_update_search_matches
    return 0
}

# *Description*:
# For row actions: ask for a value on the status line (Enter accepts, Esc
# cancels, Backspace / Ctrl-U edit).
#
# *Params*:
# - `$1`: Prompt label
# - `$2`: Initial value (optional)
#
# *Returns*:
# - `BU_RET`: the value entered
# - 1 if cancelled
bu_tv_prompt()
{
    __bu_tv_prompt_value "$@" </dev/tty >/dev/tty
}

__bu_tv_prompt_value()
{
    local -r label=$1
    local buf=${2:-} commit=false redraw=true
    _TV_PROMPT_ACTIVE=true
    _TV_PROMPT_TEXT=$label$buf
    while :
    do
        "$redraw" && __bu_tv_render
        redraw=true
        __bu_tv_read_key 1
        if "$_TV_EOF"
        then
            _TV_QUIT=true
            break
        fi
        case "$_TV_KEY" in
        none)
            __bu_tv_process_signals
            "$_TV_QUIT" && break
            ;;
        $'\x0a') commit=true; break ;;
        escape|$'\e') break ;;
        $'\x7f'|$'\x08') buf=${buf%?} ;;
        $'\x15') buf= ;;
        *)
            if (( ${#_TV_KEY} != 1 )) || [[ "$_TV_KEY" != [[:print:]] ]]
            then
                redraw=false
                continue
            fi
            buf+=$_TV_KEY
            ;;
        esac
        _TV_PROMPT_TEXT=$label$buf
    done
    _TV_PROMPT_ACTIVE=false
    _TV_PROMPT_TEXT=
    BU_RET=$buf
    "$commit"
}

# ── Preview pane ─────────────────────────────────────────────────────────

# *Description*:
# Find the terminal multiplexer that can hold a preview pane, once: tmux or
# zellij.  Nested, the innermost one owns the viewer's terminal: tmux when
# its pane's tty is ours, else zellij.
#
# *Returns*:
# - `_TV_PREVIEW_MUX`: tmux, zellij or none
__bu_tv_preview_mux()
{
    [[ -n "$_TV_PREVIEW_MUX" ]] && return 0
    _TV_PREVIEW_MUX=none
    local in_tmux=false in_zellij=false mine= pane_tty=
    [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] && command -v tmux >/dev/null && in_tmux=true
    [[ -n "${ZELLIJ:-}" ]] && command -v zellij >/dev/null && in_zellij=true
    if "$in_tmux" && "$in_zellij"
    then
        mine=$(ps -o tty= -p $$ 2>/dev/null)
        mine=${mine// /}
        pane_tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
        if [[ -n "$mine" && "$pane_tty" == */"$mine" ]]
        then
            _TV_PREVIEW_MUX=tmux
        else
            _TV_PREVIEW_MUX=zellij
        fi
    elif "$in_tmux"
    then
        _TV_PREVIEW_MUX=tmux
    elif "$in_zellij"
    then
        _TV_PREVIEW_MUX=zellij
    fi
    return 0
}

# *Description*:
# Whether a preview pane can open: a --preview command, inside tmux or
# zellij.
__bu_tv_preview_available()
{
    [[ -n "$_TV_PREVIEW_CMD" ]] || return 1
    __bu_tv_preview_mux
    [[ "$_TV_PREVIEW_MUX" != none ]]
}

# *Description*:
# Open the preview pane, or close it if open.  Without a --preview command,
# or outside tmux and zellij, only say why on the status line.
__bu_tv_preview_toggle()
{
    if [[ -n "$_TV_PREVIEW_PANE" ]]
    then
        __bu_tv_preview_close
    elif [[ -z "$_TV_PREVIEW_CMD" ]]
    then
        _TV_MESSAGE='No preview: bu view-table --preview COMMAND'
    elif ! __bu_tv_preview_available
    then
        _TV_MESSAGE='Preview needs tmux or zellij'
    else
        __bu_tv_preview_open
    fi
    return 0
}

# *Description*:
# Open a pane to the right of the viewer's, keeping the focus in the
# viewer.  The pane runs only a placeholder, which writes its tty and pid
# to _TV_PREVIEW_TTY_FILE (neither multiplexer reports both the same way):
# __bu_tv_preview_sync draws on that tty.
__bu_tv_preview_open()
{
    local pane=
    _TV_PREVIEW_TTY_FILE=${BU_TMP_DIR:-/tmp}/tv-preview-tty.$$
    rm -f "$_TV_PREVIEW_TTY_FILE"
    local -r -a placeholder=(sh -c 'printf "%s %s\n" "$(tty)" "$$" > "$0"; exec sleep 2147483647' "$_TV_PREVIEW_TTY_FILE")
    case "$_TV_PREVIEW_MUX" in
    tmux)
        pane=$(tmux split-window -h -d -l 50% -t "$TMUX_PANE" -P -F '#{pane_id}' \
            "${placeholder[@]}" 2>/dev/null) || pane=
        ;;
    zellij)
        pane=$(zellij run --no-focus --near-current-pane --direction right \
            --close-on-exit --name preview -- "${placeholder[@]}" 2>/dev/null) || pane=
        ;;
    esac
    if [[ -z "$pane" ]]
    then
        _TV_MESSAGE="Could not open a $_TV_PREVIEW_MUX pane for the preview"
        return 0
    fi
    _TV_PREVIEW_PANE=$pane
    _TV_PREVIEW_STALE=true
    [[ -n "$_TV_PREVIEW_GEN_FILE" ]] || _TV_PREVIEW_GEN_FILE=${BU_TMP_DIR:-/tmp}/tv-preview.$$
    # The viewer's pane just got narrower
    _TV_RESIZE_PENDING=true
    return 0
}

# *Description*:
# Close the preview pane (if open) and stop its pending job.
__bu_tv_preview_close()
{
    [[ -n "$_TV_PREVIEW_PANE" ]] || return 0
    (( _TV_PREVIEW_PID )) && kill "$_TV_PREVIEW_PID" 2>/dev/null
    _TV_PREVIEW_PID=0
    case "$_TV_PREVIEW_MUX" in
    tmux)   tmux kill-pane -t "$_TV_PREVIEW_PANE" 2>/dev/null ;;
    zellij) zellij action close-pane --pane-id "$_TV_PREVIEW_PANE" 2>/dev/null ;;
    esac
    _TV_PREVIEW_PANE=
    rm -f "$_TV_PREVIEW_GEN_FILE" "$_TV_PREVIEW_TTY_FILE"
    _TV_RESIZE_PENDING=true
    return 0
}

# *Description*:
# After a render: when the cursor record changed (or the pane was resized),
# start a background job drawing its preview, superseding any job still
# running.  The event loop renders once per drained batch of keys, so a
# held key starts one job per frame, not one per row.
__bu_tv_preview_sync()
{
    [[ -n "$_TV_PREVIEW_PANE" ]] || return 0
    __bu_tv_cursor_data
    local record=
    (( _TV_FOUND_IDX >= 0 )) && record=${_TV_ROWS[_TV_FOUND_IDX]}
    if ! "$_TV_PREVIEW_STALE" && [[ "$record" == "$_TV_PREVIEW_LAST" ]]
    then
        return 0
    fi
    _TV_PREVIEW_STALE=false
    _TV_PREVIEW_LAST=$record
    (( _TV_PREVIEW_PID )) && kill "$_TV_PREVIEW_PID" 2>/dev/null
    _TV_PREVIEW_GEN=$((_TV_PREVIEW_GEN + 1))
    printf '%s' "$_TV_PREVIEW_GEN" > "$_TV_PREVIEW_GEN_FILE"
    __bu_tv_preview_job "$_TV_PREVIEW_GEN" "$record" </dev/null >/dev/null 2>&1 &
    _TV_PREVIEW_PID=$!
    return 0
}

# *Description*:
# Background job: run the preview command on a record and draw its output
# on the preview pane's tty, clipped to the pane.  Gives up as soon as a
# newer job has started, so a superseded preview is never drawn, and when
# the placeholder is gone (pane closed), so a reused tty is never drawn on.
#
# *Params*:
# - `$1`: Generation of this job
# - `$2`: Record (JSON; empty: no rows, clear the pane)
__bu_tv_preview_job()
{
    local -r gen=$1 record=$2
    local tty= pid= size= out= frame line
    local -i w=0 h=0 i
    local -a lines=()
    # Let a held key move on before doing any work
    sleep 0.05
    [[ "$(< "$_TV_PREVIEW_GEN_FILE")" == "$gen" ]] || return 0
    # A new pane's placeholder may not have reported its tty yet
    for (( i = 0; i < 40; i++ ))
    do
        [[ -s "$_TV_PREVIEW_TTY_FILE" ]] && break
        sleep 0.05
    done
    read -r tty pid < "$_TV_PREVIEW_TTY_FILE" 2>/dev/null
    [[ -c "$tty" && -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || return 0
    size=$(stty size < "$tty" 2>/dev/null) || return 0
    read -r h w <<<"$size"
    (( h > 0 && w > 0 )) || return 0
    if [[ -n "$record" ]]
    then
        out=$(COLUMNS=$w LINES=$h __bu_tv_eval_action "$_TV_PREVIEW_CMD" "$record" 2>&1)
    fi
    [[ "$(< "$_TV_PREVIEW_GEN_FILE")" == "$gen" ]] || return 0
    kill -0 "$pid" 2>/dev/null || return 0
    # SO/SI (tput sgr0 under screen/tmux emits SI) would switch charsets
    mapfile -t lines < <(expand <<<"${out//[$'\016\017']/}")
    # Plain lines are clipped to the width here; autowrap off clips the rest
    # (it would leave a long line's last character in the last column). No
    # newline after the last line, so nothing scrolls off the top
    frame=$'\e[?7l\e[?25l\e[0m\e[H\e[2J'
    for (( i = 0; i < h && i < ${#lines[@]}; i++ ))
    do
        line=${lines[i]%$'\r'}
        [[ "$line" == *$'\e'* ]] || line=${line:0:w}
        (( i )) && frame+=$'\n'
        frame+=$line
    done
    printf '%s\e[0m' "$frame" > "$tty"
}

# *Description*:
# For row actions: run an interactive program (e.g. $EDITOR) on the real
# terminal, leaving the viewer's screen while it runs.
#
# *Params*:
# - `$@`: Command and arguments
#
# *Returns*:
# - The command's exit status
bu_tv_interactive()
{
    local -i rc=0
    __bu_tv_terminal_leave_tui >/dev/tty
    # Ctrl-C reaches the program, not the viewer's quit trap
    trap ':' SIGINT
    "$@" </dev/tty >/dev/tty 2>&1 || rc=$?
    trap '_TV_QUIT=true' SIGINT
    stty -echo -icanon 2>/dev/null </dev/tty || true
    {
        printf '%s' "$__BU_TV_ALT_SCREEN_ON" "$__BU_TV_CURSOR_HIDE"
        "$_TV_MOUSE" && printf '%s' "$__BU_TV_MOUSE_ON"
        printf '%s%s' "$__BU_TV_CURSOR_HOME" "$__BU_TV_CLEAR_SCREEN"
    } >/dev/tty
    _TV_RESIZE_PENDING=true
    return "$rc"
}

# ── Dispatch ─────────────────────────────────────────────────────────────

# *Description*:
# Dispatch one table-mode keypress (in _TV_KEY) to its action.  Sets
# _TV_QUIT=true on q.
__bu_tv_dispatch_key()
{
    # A key hands the sidebar list back to following the viewport
    [[ "$_TV_KEY" != mouse ]] && _TV_SIDEBAR_SCROLL=-1
    [[ "$_TV_KEY" != none && "$_TV_KEY" != mouse ]] && _TV_MESSAGE=
    local action_key
    for action_key in "${_TV_ACTION_KEYS[@]}"
    do
        if [[ "$_TV_KEY" == "$action_key" ]]
        then
            __bu_tv_run_action "$action_key"
            return 0
        fi
    done
    __bu_tv_data_rows
    local -r -i page=$_TV_DATA_ROWS
    local -i half=$((page / 2))
    (( half < 1 )) && half=1

    case "$_TV_KEY" in
    q|Q)
        _TV_QUIT=true ;;

    # Cursor
    j|down)          __bu_tv_move 1 0 ;;
    k|up)            __bu_tv_move -1 0 ;;
    h|left)          __bu_tv_move 0 -1 ;;
    l|right)         __bu_tv_move 0 1 ;;
    g)               _TV_CUR_ROW=0; __bu_tv_clamp_offsets ;;
    G)               _TV_CUR_ROW=$((_TV_NUM_VIEW - 1)); __bu_tv_clamp_offsets ;;
    0|home)          _TV_CUR_COL=0; __bu_tv_clamp_offsets ;;
    '$'|end)         _TV_CUR_COL=$((_TV_NUM_COLS - 1)); __bu_tv_clamp_offsets ;;

    # Paging: cursor and viewport together; half pages move the cursor only
    $'\x20'|page_down|shift_down) __bu_tv_page_rows "$page" ;;
    b|page_up|shift_up)           __bu_tv_page_rows "-$page" ;;
    shift_right)     __bu_tv_page_cols_right ;;
    shift_left)      __bu_tv_page_cols_left ;;
    $'\x04')         __bu_tv_move "$half" 0 ;;
    $'\x15')         __bu_tv_move "-$half" 0 ;;

    # Sort the cursor column
    s)               __bu_tv_sort_cursor_col ;;
    S)               __bu_tv_sort_cursor_col desc ;;

    # Columns: widths, freeze, hide / restore, move
    w)               __bu_tv_toggle_wide ;;
    W)               __bu_tv_toggle_wide_all ;;
    f)               __bu_tv_toggle_freeze ;;
    -)               __bu_tv_hide_col ;;
    +)               __bu_tv_restore_cols ;;
    '<')             __bu_tv_shift_col -1 ;;
    '>')             __bu_tv_shift_col 1 ;;

    # Search and filter; Esc clears the search, then the filter
    /)               __bu_tv_prompt / ;;
    '?')             __bu_tv_prompt '?' ;;
    '&')             __bu_tv_prompt '&' ;;
    n)               __bu_tv_search_step forward ;;
    N)               __bu_tv_search_step backward ;;
    escape|$'\e')
        if [[ -n "$_TV_SEARCH_QUERY" ]]
        then
            __bu_tv_search_clear
        elif [[ -n "$_TV_FILTER_QUERY" ]]
        then
            __bu_tv_cursor_data
            __bu_tv_filter_to "" "$_TV_FOUND_IDX" $((_TV_CUR_ROW - _TV_ROW_OFFSET))
        fi
        ;;

    # Toggle the column sidebar; the table width changes, so re-clamp
    c)
        if "$_TV_SIDEBAR"; then _TV_SIDEBAR=false; else _TV_SIDEBAR=true; fi
        __bu_tv_clamp_offsets
        ;;
    p)               __bu_tv_preview_toggle ;;

    # Overlays
    $'\x0a')         __bu_tv_open_detail ;;
    H|f1)            __bu_tv_open_help ;;

    # Mouse
    mouse)           __bu_tv_mouse_table ;;
    m)               __bu_tv_toggle_mouse ;;

    ctrl_l)          __bu_tv_remeasure ;;
    esac
    return 0
}

# *Description*:
# Close the open overlay: help returns to where it was opened from, detail
# to the table.
__bu_tv_overlay_close()
{
    if [[ "$_TV_MODE" == help ]]
    then
        _TV_MODE=$_TV_HELP_RETURN
    else
        _TV_MODE=table
    fi
    _TV_HELP_RETURN=table
}

# *Description*:
# Dispatch one keypress in the detail or help overlay.  Both scroll (also
# with the wheel); the detail overlay also steps through records (J / K)
# and matches (n / N) without closing.  q, Q, Esc, Enter and a left click
# go back, except on a status-line hint, which presses its key.
__bu_tv_dispatch_overlay()
{
    __bu_tv_data_rows
    local -r -i page=$_TV_DATA_ROWS
    local -i half=$((page / 2))
    (( half < 1 )) && half=1
    local off_var=_TV_DETAIL_OFFSET
    [[ "$_TV_MODE" == help ]] && off_var=_TV_HELP_OFFSET
    local -n __do_off=$off_var

    case "$_TV_KEY" in
    j|down)          __do_off=$((__do_off + 1)) ;;
    k|up)            __do_off=$((__do_off - 1)) ;;
    $'\x20'|page_down|shift_down) __do_off=$((__do_off + page)) ;;
    b|page_up|shift_up)           __do_off=$((__do_off - page)) ;;
    $'\x04')         __do_off=$((__do_off + half)) ;;
    $'\x15')         __do_off=$((__do_off - half)) ;;
    g)               __do_off=0 ;;
    G)               __do_off=$((${#_TV_DETAIL_LINES[@]} + ${#_TV_HELP_LINES[@]})) ;;
    q|Q|escape|$'\e'|$'\x0a')
        __bu_tv_overlay_close
        ;;
    mouse)
        # The wheel scrolls three lines, a left press closes
        case "$_TV_MOUSE_EVENT" in
        wheel_up)   __do_off=$((__do_off - 3)) ;;
        wheel_down) __do_off=$((__do_off + 3)) ;;
        release)    _TV_SB_GRABBED=false ;;
        press)
            if (( _TV_MOUSE_BUTTON != 0 ))
            then
                :
            elif (( _TV_MOUSE_Y == _TV_TERM_ROWS ))
            then
                __bu_tv_status_hint_key "$_TV_MOUSE_X"
                [[ "$_TV_KEY" != none ]] && __bu_tv_dispatch_overlay
            else
                __bu_tv_overlay_close
            fi
            ;;
        esac
        ;;
    m)               __bu_tv_toggle_mouse ;;
    H|f1)
        if [[ "$_TV_MODE" == help ]]
        then
            _TV_MODE=$_TV_HELP_RETURN
            _TV_HELP_RETURN=table
        else
            __bu_tv_open_help
        fi
        ;;
    J)  [[ "$_TV_MODE" == detail ]] && __bu_tv_detail_record 1 ;;
    K)  [[ "$_TV_MODE" == detail ]] && __bu_tv_detail_record -1 ;;
    n)  [[ "$_TV_MODE" == detail ]] && __bu_tv_detail_match forward ;;
    N)  [[ "$_TV_MODE" == detail ]] && __bu_tv_detail_match backward ;;
    ctrl_l)          __bu_tv_remeasure ;;
    esac
    __bu_tv_overlay_clamp
    return 0
}

# *Description*:
# Dispatch one keypress (in _TV_KEY) by mode.  tty EOF quits from anywhere.
__bu_tv_dispatch()
{
    if "$_TV_EOF"
    then
        _TV_QUIT=true
        return 0
    fi
    case "$_TV_MODE" in
    detail|help)
        __bu_tv_dispatch_overlay
        ;;
    *)
        __bu_tv_dispatch_key
        ;;
    esac
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════
# Main entry point
# ═══════════════════════════════════════════════════════════════════════════

# *Description*:
# Make bash count characters, not bytes.  Under a non-UTF-8 locale (e.g. LANG
# unset) ${#var}, substring slicing and read -n 1 work on bytes while the jq
# width pass counts codepoints, so any non-ASCII cell (or the sidebar's │)
# misaligns padding and truncation.  Process-local: the cmdlet runs in its
# own process.  LC_ALL must be cleared or it overrides LC_CTYPE.
__bu_tv_ensure_utf8_ctype()
{
    local -r loc=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
    case "${loc,,}" in
    *utf-8*|*utf8*)
        ;;
    *)
        unset LC_ALL
        export LC_CTYPE=C.UTF-8
        ;;
    esac
    return 0
}

# *Description*:
# Entry point for the interactive table viewer.
#
# *Params*:
# - `$1`: Column spec (comma-separated key:Label,...) — optional
# - `$2`: Color spec (key=color,..., "auto" or "none") — optional; empty is
#         "auto", or "none" when NO_COLOR is set
# - `$3`: "false" to start with the column sidebar hidden — optional
# - `$4`: Column width cap (positive integer) — optional, default 40
#
# *Notes*:
# - Reads JSONL from stdin.
# - Blocks until the user presses q.
bu_tv_enter()
{
    local columns_spec=$1
    local colors_spec=$2
    _TV_SIDEBAR=${3:-true}
    local max_width=${4:-40}

    # The viewer manages its own error handling; errexit would break the
    # event loop and cause spurious exits on false (( ... )) guards.
    set +e

    # Reset before the traps exist; a Ctrl-C during setup then still quits
    _TV_QUIT=false
    _TV_EOF=false
    _TV_RESIZE_PENDING=false
    _TV_SUSPEND_PENDING=false
    _TV_RESUME_PENDING=false
    _TV_MODE=table
    _TV_PROMPT_ACTIVE=false
    _TV_CUR_ROW=0
    _TV_CUR_COL=0
    _TV_ROW_OFFSET=0
    _TV_COL_OFFSET=0
    _TV_COL_EXPANDED=()
    _TV_FILTER_QUERY=
    _TV_FROZEN_N=0
    _TV_HIDDEN=()

    # A leading 0 would reach integer variables as (bad) octal
    if [[ ! "$max_width" =~ ^[1-9][0-9]*$ ]]
    then
        bu_log_err "bu view-table: max width must be a positive integer, got [$max_width]"
        return 1
    fi
    (( ${#max_width} > 6 )) && max_width=999999
    _TV_MAX_WIDTH=$max_width

    __bu_tv_ensure_utf8_ctype

    # ── Load and index data ───────────────────────────────────────────
    __bu_tv_read_stdin

    if (( _TV_NUM_ROWS == 0 ))
    then
        bu_log_info "bu tv: no records to display"
        return 0
    fi

    __bu_tv_extract_columns "$columns_spec" || return 1
    if (( _TV_NUM_COLS == 0 ))
    then
        bu_log_info "bu tv: no columns found"
        return 0
    fi

    # A failed rebuild means the table would render shifted: don't start
    __bu_tv_rebuild_cache || return 1
    __bu_tv_resolve_colors "$colors_spec"
    __bu_tv_build_colors "$BU_RET" || return 1

    # ── After consuming piped stdin, switch to /dev/tty for keyboard ─
    if [[ -c /dev/tty ]]; then
        exec </dev/tty
    fi

    # ── Terminal setup ────────────────────────────────────────────────
    __bu_tv_terminal_setup || return 1
    __bu_tv_clamp_offsets
    __bu_tv_preview_available && __bu_tv_preview_open

    # ── Event loop ────────────────────────────────────────────────────
    # One render per drained input batch: after the first (blocking) key,
    # coalesce any already-queued keypresses and process them without
    # rendering, so a held key can't build a backlog of stale frames.
    while ! "$_TV_QUIT"
    do
        __bu_tv_process_signals
        "$_TV_QUIT" && break
        __bu_tv_render
        __bu_tv_preview_sync
        __bu_tv_read_key 1
        __bu_tv_dispatch
        while ! "$_TV_QUIT" && __bu_tv_read_key 0
        do
            __bu_tv_dispatch
        done
    done

    __bu_tv_terminal_restore
}
