# expect: fixed
# Base prefix followed by an unbraced expansion. `10#${month}` already worked.
x="$((10#$month))"
