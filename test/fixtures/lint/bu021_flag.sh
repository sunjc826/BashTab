#!/usr/bin/env bash
f() {
while (($#)); do
    bu_parse_multiselect $# "$1"
    case "$1" in
    --lying)# _FLAG
        bu_parse_positional $# --hint "but it takes an argument"
        value=${!shift_by}
        ;;
    --honest)# _FLAG
        is_honest=true
        ;;
    esac
    shift "$shift_by"
done
}
