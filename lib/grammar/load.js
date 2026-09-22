"use strict";

/**
 * Resolve the bash grammar: BashTab's fork when it has been built, otherwise
 * the stock parser.
 *
 * Every consumer must work without the fork — it needs a C toolchain, so it is
 * opt-in (`node lib/grammar/build.js`). Callers that care can report which one
 * they got; `bu validate-script` surfaces it as BU000 coverage.
 */

const path = require("path");

const ROOT = path.resolve(__dirname, "..", "..");
const FORK = path.join(__dirname, "build", "bindings", "node");

let cached = null;

function load(opts) {
    if (cached && !(opts && opts.force)) return cached;
    try {
        cached = { language: require(FORK), forked: true };
    } catch (e) {
        cached = { language: require(path.join(ROOT, "node_modules", "tree-sitter-bash")), forked: false };
    }
    return cached;
}

module.exports = { load };
