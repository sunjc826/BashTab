# The example host consumes gitshelf as a library, with one command registry.
# Render from the repository root with docs/render_demos.sh docs/demo-modules.tape
Output docs/demo-modules.mp4
Source docs/demos/style.tape
Env BASHTAB_DEMO_MODULE "devbox"
Source docs/demos/setup.tape

Type "devbox get-module --columns name,rank,version,branch,dirty"
Enter
Sleep 3s

Type "devbox get-command | devbox where module -in devbox,gitshelf select name,module,synopsis"
Enter
Sleep 4s

Type "devbox get-"
Tab
Sleep 2s
Type "env"
Enter
Sleep 500ms
Ctrl+U

Type "devbox get-help gitshelf"
Enter
Sleep 4s
Type "q"
Sleep 500ms
