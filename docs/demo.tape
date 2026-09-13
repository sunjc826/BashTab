# BashTab hero demo — regenerates docs/demo.gif
# Render from the repository root with docs/render_demos.sh docs/demo.tape
Output docs/demo.mp4

Source docs/demos/style.tape
Source docs/demos/setup.tape

# ── Beat 1: `bu` command listing ───────────────────────────
Type "bu"
Enter
Sleep 3.5s
# The command catalog fills the default table pager.
Type "q"
Sleep 300ms
Ctrl+L

# ── Beat 2: fzf autocomplete — verb-noun discovery ─────────
Type "bu get-"
Tab
Sleep 3s
Type "comm"
Sleep 1s
Enter
Sleep 800ms
Type " | bu where verb -eq format select name, module"
Enter
Sleep 2.5s
Ctrl+L

# ── Beat 3: structured output — SQL-style query ───────────
Type "bu query-object --from docs/demos/services.tsv where latency_ms -gt 100 select name, status, latency_ms"
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
Type "bu get-help --columns topic,module"
Enter
Sleep 3.5s

# ── Outro ──────────────────────────────────────────────────
Ctrl+L
Type "bu get-version"
Enter
Sleep 3s
