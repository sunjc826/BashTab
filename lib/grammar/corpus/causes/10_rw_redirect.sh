# expect: fixed
# The <> read-write redirect, with a {varname} descriptor.
exec {BU_PROC_FIFO_FD}<>"$BU_PROC_FIFO"
