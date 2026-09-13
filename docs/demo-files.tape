# File-backed queries: header inference, field completion, and numeric filtering.
# Render from the repository root with docs/render_demos.sh docs/demo-files.tape
Output docs/demo-files.mp4
Source docs/demos/style.tape
Source docs/demos/setup.tape

Type "bu import-tsv docs/demos/services.tsv"
Enter
Sleep 2s

# The menu comes from the TSV header, without registering a producer.
Type "bu query-object --from docs/demos/services.tsv select "
Tab
Sleep 2s
Type "name"
Enter
Sleep 500ms
Type ", status, latency_ms"
Enter
Sleep 3s

Ctrl+L
Type "bu import-tsv docs/demos/services.tsv | bu where latency_ms -gt 100 select name, latency_ms"
Enter
Sleep 3s

# JSON preserves numeric types for averages (TSV fields are strings).
# Grouping, named aggregates, and flexible comma placement across words.
Type "bu query-object --from docs/demos/services.json group-by team agg count, avg:latency_ms order-by count desc"
Enter
Sleep 4s
