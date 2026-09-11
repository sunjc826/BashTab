# BashTab demo: query-object interactive DSL — regenerates docs/demo-query.gif
# Render via docs/render_demos.sh (tapes Output .mp4; ffmpeg converts to .gif
# because vhs's built-in GIF encoder produces 0-byte files in some containers).
# Container note: if chromium fails with a namespace/sandbox error, run as
#   PATH=/tmp/vhs-bin:$PATH vhs docs/demo-query.tape   (wrapper that adds --no-sandbox)
# Interaction notes (verified via tmux):
# - fzf selections and inline completions insert NOSPACE: Type " " before next Tab
# - a unique typed prefix (e.g. "whe") completes inline with no fzf box —
#   to show the clause box, Tab on an empty word, then Escape to dismiss

Output docs/demo-query.mp4

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
Type " get-*"
Sleep 500ms

# ── Beat 7: finish with a projection and run the query ─────
Type " select name,verb,namespace"
Enter
Sleep 3.5s

# ── Outro: hold the final frame ────────────────────────────
Sleep 2s
