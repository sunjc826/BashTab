# BashTab demo: external command completion (Fig specs + --help parsing)
# Render from the repository root with docs/render_demos.sh docs/demo-external.tape
Output docs/demo-external.mp4

Source docs/demos/style.tape
Source docs/demos/setup.tape

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
