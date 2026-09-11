# BashTab demo: help-topic subsystem — regenerates docs/demo-help.gif
# Render via docs/render_demos.sh (tapes Output .mp4; ffmpeg converts to .gif
# because vhs's built-in GIF encoder produces 0-byte files in some containers).
# Container note: if chromium fails with a namespace/sandbox error, run as
#   PATH=/tmp/vhs-bin:$PATH vhs docs/demo-help.tape

Output docs/demo-help.mp4

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

# ── Beat 1: help topic listing ─────────────────────────────
Type "bu get-help"
Enter
Sleep 3.5s

# ── Beat 2: topic detail (pages; q quits the pager) ────────
Type "bu get-help pipeline"
Enter
Sleep 4.5s
Type "q"
Sleep 500ms

# ── Beat 3: autohelp generated from the parser definition ──
Type "clear"
Enter
Type "bu query-object --help"
Enter
Sleep 5s

# ── Outro: hold the final frame ────────────────────────────
Sleep 2s
