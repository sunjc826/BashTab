# BashTab demo: external command completion (Fig specs + --help parsing)
# — regenerates docs/demo-external.gif
# Render via docs/render_demos.sh (tapes Output .mp4; ffmpeg converts to .gif
# because vhs's built-in GIF encoder produces 0-byte files in some containers).
# Container note: if chromium fails with a namespace/sandbox error, run as
#   PATH=/tmp/vhs-bin:$PATH vhs docs/demo-external.tape

Output docs/demo-external.mp4

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

# ── Beat 1: docker subcommands, described ─────────────────
Type "docker "
Tab
Sleep 3.5s
Escape
Sleep 300ms
Ctrl+U
Sleep 300ms

# ── Beat 2: docker run options with live preview ──────────
Type "docker run --"
Tab
Sleep 3s
Type "vol"
Sleep 1.5s
Escape
Sleep 300ms
Ctrl+U
Sleep 300ms

# ── Beat 3: git subcommands ───────────────────────────────
Type "git ch"
Tab
Sleep 3s
Escape
Sleep 300ms
Ctrl+U
Sleep 300ms

# ── Beat 4: git log options with preview ──────────────────
Type "git log --"
Tab
Sleep 3s
Type "grep"
Sleep 1.5s

# ── Outro: hold the final frame ────────────────────────────
Sleep 2s
