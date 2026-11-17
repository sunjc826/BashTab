# expect: unfixed
# `|` inside a :+ expansion default.
x="${M[$n,enum]:-${M[$n,bool]:+true|false}}"
