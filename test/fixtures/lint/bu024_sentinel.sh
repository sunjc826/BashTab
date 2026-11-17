#!/usr/bin/env bash
f() {
bu_parse_positional $# --enum alpha beta
bu_parse_positional $# --enum alpha beta enum--
}
