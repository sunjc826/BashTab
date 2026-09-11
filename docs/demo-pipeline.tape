# BashTab demo: structured output pipeline — regenerates docs/demo-pipeline.gif
# Render via docs/render_demos.sh (tapes Output .mp4; ffmpeg converts to .gif
# because vhs's built-in GIF encoder produces 0-byte files in some containers).
# Container note: if chromium fails with a namespace/sandbox error, run as
#   PATH=/tmp/vhs-bin:$PATH vhs docs/demo-pipeline.tape

Output docs/demo-pipeline.mp4

Set Shell "bash"
Set FontSize 16
Set Width 1600
Set Height 900
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms

# ── Invisible pre-roll: activate BashTab and prepare a clean prompt ──
Hide
Type@0ms "export BU_MODULE_PATH=; source ./activate 2>/dev/null"
Enter
Sleep 2s
Type@0ms "PROMPT_COMMAND=; PS1='$ '; clear"
Enter
Show
Sleep 500ms

# ── Beat 1: records render as a table on a terminal ───────
Type "bu get-command"
Enter
Sleep 3.5s

# ── Beat 2: the same command piped emits JSONL (Out-Default) ─
# (tail -3, not head -3: head causes a visible jq broken-pipe error)
Type "bu get-command | tail -3"
Enter
Sleep 2.5s

# ── Beat 3: field completion after a pipe, comma multiselect ─
Type "bu get-command | bu select name,"
Tab
Sleep 2s
Type "syn"
Sleep 1s
Enter
Sleep 800ms
Enter
Sleep 3s

# ── Beat 4: SQL-style query — group-by, agg, having, order-by ─
Type "clear"
Enter
Type "bu get-command | bu query-object group-by verb agg count having count -gt 5 order-by count desc"
Enter
Sleep 3.5s

# ── Beat 5: grep clause — match a pattern across any field ─
Type "bu get-command | bu grep docker select name,synopsis"
Enter
Sleep 3.5s

# ── Outro: hold the final frame ────────────────────────────
Sleep 2s
