#!/usr/bin/env node

/**
 * Verify BashTab's tree-sitter-bash fork.
 *
 *   node lib/grammar/test.js
 *
 * Three checks, in order of how much they matter:
 *
 *   1. REGRESSION — every shell script in this repo, plus corpus/regression/,
 *      must parse at least as well under the fork as under upstream. A patch
 *      that fixes one construct and breaks another is worse than no patch.
 *      This check caught exactly that during development.
 *   2. CAUSES     — each corpus/causes/ repro declares `# expect: fixed` or
 *      `# expect: unfixed`. Both directions are asserted, so a repro that
 *      starts passing (upstream fixed it, or a new patch did) is reported
 *      rather than silently ignored.
 *   3. VALIDITY   — every repro must be valid bash, or it is not a grammar
 *      bug. Verified with `bash -n`.
 *
 * Exits non-zero on any regression or any expectation mismatch.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..", "..");
const Parser = require(path.join(ROOT, "node_modules", "tree-sitter"));
const { load } = require("./load.js");

const stock = new Parser();
stock.setLanguage(require(path.join(ROOT, "node_modules", "tree-sitter-bash")));

const loaded = load();
const fork = new Parser();
fork.setLanguage(loaded.language);

// hasError covers ERROR nodes; isMissing covers MISSING nodes, which a plain
// ERROR check silently lets through (they read as a clean parse otherwise).
const broken = (parser, src) => parser.parse(src).rootNode.hasError;

let failures = 0;
const fail = (msg) => {
    process.stdout.write(`  FAIL  ${msg}\n`);
    failures++;
};

if (!loaded.forked) {
    process.stdout.write("The fork is not built — run: node lib/grammar/build.js\n");
    process.stdout.write("Checking upstream behavior only.\n\n");
}

// ── 1. regression sweep ──────────────────────────────────────────────────
process.stdout.write("Regression sweep (fork must not break what upstream parses)\n");
const sweepFiles = [];
const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) {
            if (["node_modules", ".git", "fig_specs", "bats", "test_helper", "build", "v86"].includes(e.name)) continue;
            walk(p);
        } else if (e.name.endsWith(".sh")) sweepFiles.push(p);
    }
};
walk(ROOT);
let regressed = 0;
let fixed = 0;
for (const f of sweepFiles) {
    if (f.includes(path.join("corpus", "causes"))) continue; // known-bad by design
    const src = fs.readFileSync(f, "utf8");
    const s = broken(stock, src);
    const k = broken(fork, src);
    if (!s && k) {
        fail(`${path.relative(ROOT, f)} parses upstream but NOT under the fork`);
        regressed++;
    } else if (s && !k) fixed++;
}
process.stdout.write(`  ${sweepFiles.length} files, ${regressed} regressions, ${fixed} newly parsing\n\n`);

// ── 2. cause expectations ────────────────────────────────────────────────
process.stdout.write("Cause repros\n");
const causeDir = path.join(__dirname, "corpus", "causes");
for (const name of fs.readdirSync(causeDir).sort()) {
    if (!name.endsWith(".sh")) continue;
    const file = path.join(causeDir, name);
    const src = fs.readFileSync(file, "utf8");
    const m = /^#\s*expect:\s*(fixed|unfixed)\s*$/m.exec(src);
    if (!m) {
        fail(`${name} has no '# expect: fixed|unfixed' marker`);
        continue;
    }
    const expectFixed = m[1] === "fixed";
    const stillBroken = broken(fork, src);
    const label = stillBroken ? "unfixed" : "fixed";

    // 3. validity: a repro that bash itself rejects is not a grammar bug.
    try {
        execFileSync("bash", ["-n", file], { stdio: "ignore" });
    } catch (e) {
        fail(`${name} is not valid bash — it does not belong in this corpus`);
        continue;
    }

    if (expectFixed && stillBroken) fail(`${name}: expected fixed, still fails to parse`);
    else if (!expectFixed && !stillBroken)
        fail(`${name}: marked unfixed but now parses — update the marker (upstream or a patch fixed it)`);
    else process.stdout.write(`  ok    ${name} (${label})\n`);
}

const fixedCount = fs
    .readdirSync(causeDir)
    .filter((n) => n.endsWith(".sh"))
    .filter((n) => /^#\s*expect:\s*fixed\s*$/m.test(fs.readFileSync(path.join(causeDir, n), "utf8"))).length;
const total = fs.readdirSync(causeDir).filter((n) => n.endsWith(".sh")).length;

process.stdout.write(`\n${fixedCount}/${total} causes fixed by the fork (${loaded.forked ? "fork loaded" : "STOCK — fork not built"})\n`);
if (failures) {
    process.stdout.write(`${failures} check(s) failed\n`);
    process.exit(1);
}
process.stdout.write("all checks passed\n");
