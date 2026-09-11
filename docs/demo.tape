# BashTab hero demo — regenerates docs/demo.gif
# Render via docs/render_demos.sh (tapes Output .mp4; ffmpeg converts to .gif
# because vhs's built-in GIF encoder produces 0-byte files in some containers).
# Requires: vhs, ttyd, ffmpeg (https://github.com/charmbracelet/vhs)
# Container note: if chromium fails with a namespace/sandbox error, run as
#   PATH=/tmp/vhs-bin:$PATH vhs docs/demo.tape   (wrapper that adds --no-sandbox)
# Note: fzf selections insert NOSPACE — after selecting a command, Enter runs it.

Output docs/demo.mp4

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

# ── Beat 1: `bu` command listing ───────────────────────────
Type "bu"
Enter
Sleep 3.5s
Type "clear"
Enter

# ── Beat 2: fzf autocomplete — verb-noun discovery ─────────
Type "bu get-"
Tab
Sleep 3s
Type "proc"
Sleep 1s
Enter
Sleep 800ms
Enter
Sleep 2.5s
Type "clear"
Enter

# ── Beat 3: structured output — SQL-style query ───────────
Type "bu get-process | bu query-object where mem_percent -gt 1 select pid,command,mem_percent order-by mem_percent desc first 5"
Enter
Sleep 4s

# ── Beat 4: external commands — docker options with preview ─
Type "docker run --"
Tab
Sleep 3s
Escape
Sleep 300ms
Ctrl+U
Sleep 300ms

# ── Beat 5: help topics ────────────────────────────────────
Type "bu get-help"
Enter
Sleep 3.5s

# ── Outro ──────────────────────────────────────────────────
Type "clear"
Enter
Type "bu get-version"
Enter
Sleep 3s
