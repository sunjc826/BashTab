# BashTab demo: structured output pipeline — regenerates docs/demo-pipeline.gif
# Render from the repository root with docs/render_demos.sh docs/demo-pipeline.tape
Output docs/demo-pipeline.mp4

Source docs/demos/style.tape
Source docs/demos/setup.tape

# ── Beat 1: records render as a table on a terminal ───────
Type "bu get-command | bu where verb -eq format select name,verb"
Enter
Sleep 3.5s

# ── Beat 2: the same command piped emits JSONL (Out-Default) ─
# Use the same small result set before displaying raw JSONL.
Type "bu get-command | bu where verb -eq format select name,verb | cat"
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
Type " where verb -eq format"
Enter
Sleep 3s

# ── Beat 4: SQL-style query — group-by, agg, having, order-by ─
Ctrl+L
Type "bu get-command | bu query-object group-by verb agg count having count -gt 10 order-by count desc"
Enter
Sleep 3.5s

# ── Beat 5: grep clause — match a pattern across any field ─
Type "bu get-command | bu grep docker select name,synopsis"
Enter
Sleep 3.5s

# ── Beat 6: shareable table styles ─────────────────────────
Ctrl+L
Type "bu import-tsv docs/demos/services.tsv | bu format-table --style double --columns name,status"
Enter
Sleep 3s
Type "bu import-tsv docs/demos/services.tsv | bu format-table --style markdown --columns name,status"
Enter
Sleep 3s
