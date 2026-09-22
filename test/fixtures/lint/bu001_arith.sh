#!/usr/bin/env bash
# Only the bare statement-position increment is a finding.
count=0
((count++))
x=$((count++))
if ((count > 0)); then echo yes; fi
while ((count < 5)); do : $((count++)); done
: $((count++))
for f in a b; do sum[$f]=1; ((count++)); done
