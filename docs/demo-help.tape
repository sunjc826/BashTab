# BashTab demo: help-topic subsystem — regenerates docs/demo-help.gif
# Render from the repository root with docs/render_demos.sh docs/demo-help.tape
Output docs/demo-help.mp4

Source docs/demos/style.tape
Source docs/demos/setup.tape

# ── Beat 1: help topic listing ─────────────────────────────
Type "bu get-help --columns topic,synopsis,module"
Enter
Sleep 3.5s

# ── Beat 2: topic detail (pages; q quits the pager) ────────
Type "bu get-help pipeline"
Enter
Sleep 4.5s
Type "q"
Sleep 500ms

# ── Beat 3: autohelp generated from the parser definition ──
Ctrl+L
# Autohelp's example formatter currently warns while resolving absolute script
# paths. Its generated stdout page is the subject of this clip.
Type "bu format-table --help 2>/dev/null | less -R"
Enter
Sleep 4s
Space
Sleep 3s
Type "q"

# ── Outro: hold the final frame ────────────────────────────
Sleep 2s
