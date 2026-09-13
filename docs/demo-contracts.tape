# Pipeline contracts: compatible commands, static diagnostics, and observed types.
# Render from the repository root with docs/render_demos.sh docs/demo-contracts.tape
Output docs/demo-contracts.mp4
Source docs/demos/style.tape
Source docs/demos/setup.tape

# After TSV output, completion offers compatible recordifiers.
Type "bu get-command | bu convert-to-tsv | bu "
Tab
Sleep 2s
Type "convert-from"
Sleep 2s
Escape
Sleep 300ms
Ctrl+U

Type "bu validate-pipeline 'bu get-command | bu select name,verb | bu sort typo'"
Enter
Sleep 3s
Type "bu validate-pipeline 'bu get-command | bu select name,verb | bu sort name'"
Enter
Sleep 2s

Type "bu get-shape get-process --columns name,type,required"
Enter
Sleep 4s
