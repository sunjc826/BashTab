# Opt-in Alt+T selector; setup registers wrap-timeout and its automatic inverse.
# Render from the repository root with docs/render_demos.sh docs/demo-transforms.tape
Output docs/demo-transforms.mp4
Source docs/demos/style.tape
Env BASHTAB_DEMO_TRANSFORMS "true"
Source docs/demos/setup.tape

Type "bu get-transform --columns name,match,replace,derived"
Enter
Sleep 3s

Type "printf '%s\n' 'hello BashTab'"
Alt+t
Sleep 2s
Type "^wrap-timeout"
Sleep 2s
Enter
Sleep 2s

# Unwrap restores the original quoting before the command is executed.
Alt+t
Sleep 1s
Type "^unwrap-timeout"
Sleep 2s
Enter
Sleep 2s
Enter
Sleep 3s
