# BashTab demo: query-object interactive DSL — regenerates docs/demo-query.gif
# Render from the repository root with docs/render_demos.sh docs/demo-query.tape
Output docs/demo-query.mp4

Source docs/demos/style.tape
Source docs/demos/setup.tape

# ── Beat 1: clause keyword box on query-object ─────────────
Type "bu get-command | bu query-object "
Tab
Sleep 2.5s
Type "where"
Sleep 1.5s
Escape
Sleep 500ms

# ── Beat 2: inline-complete bare `where`, then field names ─
Type "whe"
Tab
Sleep 800ms
Type " "
Tab
Sleep 2s
Type "type"
Sleep 1s
Enter
Sleep 500ms

# ── Beat 3: binary operator completion ──────────────────────
Type " "
Tab
Sleep 2s
Type "eq"
Sleep 1s
Enter
Sleep 500ms

# ── Beat 4: distinct field-value completion (tab-execute) ──
Type " "
Tab
Sleep 2.5s
Type "sour"
Sleep 1s
Enter
Sleep 500ms

# ── Beat 5: and/or connector completion ─────────────────────
Type " "
Tab
Sleep 2s
Enter
Sleep 500ms

# ── Beat 6: second condition — field, operator, glob value ──
Type " "
Tab
Sleep 1.5s
Type "name"
Sleep 500ms
Enter
Sleep 300ms
Type " "
Tab
Sleep 1.5s
Type "like"
Sleep 500ms
Enter
Sleep 300ms
Type " get-docker-*"
Sleep 500ms

# ── Beat 7: finish with a projection and run the query ─────
Type " select name, verb, module"
Enter
Sleep 3.5s

# ── Outro: hold the final frame ────────────────────────────
Sleep 2s
