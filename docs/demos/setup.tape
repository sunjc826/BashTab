# Hidden activation; import style.tape before any per-clip Env directives.
Hide
Type@0ms "source docs/demos/setup.sh"
Enter
# Activation must finish AND clear the screen before frames are captured.
# Matching the final prompt avoids fixed sleeps that leak setup on slow hosts.
Wait+Line@60s /^\$\s*$/
Sleep 200ms
Show
Sleep 300ms
