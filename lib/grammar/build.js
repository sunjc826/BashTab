#!/usr/bin/env node

/**
 * Build, check, or rebase BashTab's vendored tree-sitter-bash fork.
 *
 *   node lib/grammar/build.js            compile vendor/ into out/
 *   node lib/grammar/build.js --check    assert vendored == upstream + patches
 *   node lib/grammar/build.js --rebase   re-derive vendor/ from current upstream
 *
 * The fork itself lives in vendor/ and is committed. patches.js is the
 * derivation record: --check re-applies it to the installed upstream package
 * and diffs the result against vendor/, so the vendored file cannot silently
 * drift from a patch set that no longer describes it.
 *
 * Building requires a C toolchain; see lib/grammar/README.md. Nothing else in
 * BashTab requires one — load.js falls back to the stock parser.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..", "..");
const VENDOR = path.join(__dirname, "vendor");
const OUT = path.join(__dirname, "out");
const UPSTREAM = path.join(ROOT, "node_modules", "tree-sitter-bash");
const TS_CLI = path.join(ROOT, "node_modules", ".bin", "tree-sitter");
const PATCHES = require("./patches.js");

const mode = process.argv.includes("--check") ? "check" : process.argv.includes("--rebase") ? "rebase" : "build";
const log = (m) => process.stderr.write(`bu grammar: ${m}\n`);
const die = (m) => {
    process.stderr.write(`bu grammar: ${m}\n`);
    process.exit(1);
};

/** Apply the patch set to upstream's grammar.js, asserting every anchor. */
function derive() {
    if (!fs.existsSync(UPSTREAM)) die(`tree-sitter-bash is not installed — run 'pnpm install' in ${ROOT}`);
    let out = fs.readFileSync(path.join(UPSTREAM, "grammar.js"), "utf8");
    for (const p of PATCHES) {
        const hits = out.split(p.find).length - 1;
        if (hits === 0) {
            die(
                `patch '${p.id}' no longer applies — upstream changed the code it anchors on.\n` +
                    `  ${p.summary}\n` +
                    `  Fix the 'find' string in lib/grammar/patches.js, or drop the patch if upstream\n` +
                    `  has fixed it (node lib/grammar/test.js reports repros that start passing).`
            );
        }
        if (hits > 1) die(`patch '${p.id}' anchor is ambiguous (${hits} matches) — make it more specific`);
        out = out.replace(p.find, p.replace);
    }
    return out;
}

const upstreamVersion = () =>
    fs.existsSync(UPSTREAM) ? require(path.join(UPSTREAM, "package.json")).version : "(not installed)";

// ── --check ──────────────────────────────────────────────────────────────
if (mode === "check") {
    const derived = derive();
    const vendored = fs.readFileSync(path.join(VENDOR, "grammar.js"), "utf8");
    if (derived !== vendored) {
        die(
            "vendor/grammar.js does not match upstream + patches.js.\n" +
                "  Either upstream moved (adopt it: node lib/grammar/build.js --rebase)\n" +
                "  or the vendored file was hand-edited (fold the edit into patches.js).\n" +
                `  upstream: tree-sitter-bash ${upstreamVersion()}`
        );
    }
    const upScanner = fs.readFileSync(path.join(UPSTREAM, "src", "scanner.c"), "utf8");
    const vendorScanner = fs.readFileSync(path.join(VENDOR, "src", "scanner.c"), "utf8");
    log(`vendor/grammar.js == upstream ${upstreamVersion()} + ${PATCHES.length} patches`);
    log(vendorScanner === upScanner ? "vendor/src/scanner.c is unmodified upstream" : "vendor/src/scanner.c DIVERGES from upstream (intentional?)");
    process.exit(0);
}

// ── --rebase ─────────────────────────────────────────────────────────────
if (mode === "rebase") {
    const derived = derive();
    fs.writeFileSync(path.join(VENDOR, "grammar.js"), derived);
    const provenance = {
        upstream: { package: "tree-sitter-bash", version: upstreamVersion() },
        patches: PATCHES.map((p) => p.id),
        note: "Regenerate with: node lib/grammar/build.js --rebase",
    };
    fs.writeFileSync(path.join(VENDOR, "PROVENANCE.json"), JSON.stringify(provenance, null, 2) + "\n");
    log(`vendor/grammar.js re-derived from tree-sitter-bash ${upstreamVersion()}`);
    log("scanner.c is NOT touched by --rebase; diff it against upstream yourself if you have patched it");
    log("next: node lib/grammar/build.js && node lib/grammar/test.js");
    process.exit(0);
}

// ── build ────────────────────────────────────────────────────────────────
if (!fs.existsSync(path.join(VENDOR, "grammar.js"))) die("vendor/grammar.js is missing — this checkout is incomplete");

fs.rmSync(OUT, { recursive: true, force: true });
fs.cpSync(VENDOR, OUT, { recursive: true });
// node-addon-api is resolved from the repo's node_modules at compile time.
const link = path.join(OUT, "node_modules");
if (!fs.existsSync(link)) fs.symlinkSync(path.join(ROOT, "node_modules"), link, "dir");
log("staged vendor/ into out/");

const run = (cmd, args) => {
    try {
        execFileSync(cmd, args, { cwd: OUT, stdio: ["ignore", "ignore", "pipe"] });
    } catch (e) {
        const detail = (e.stderr || Buffer.from("")).toString().trim().split("\n").slice(0, 12).join("\n");
        die(`${path.basename(cmd)} failed:\n${detail}`);
    }
};

if (!fs.existsSync(TS_CLI)) die("tree-sitter CLI not found — is tree-sitter-cli installed?");
run(TS_CLI, ["generate"]);
log("parser generated from vendor/grammar.js");

const localGyp = path.join(ROOT, "node_modules", ".bin", "node-gyp");
if (fs.existsSync(localGyp)) {
    run(localGyp, ["rebuild"]);
} else {
    log("node-gyp not installed locally — fetching it with npx (first build only, needs network)");
    run("npx", ["--yes", "node-gyp", "rebuild"]);
}
log("parser compiled");

const { load } = require("./load.js");
const { language, forked } = load({ force: true });
if (!forked) die("built the fork but could not load it");
const Parser = require(path.join(ROOT, "node_modules", "tree-sitter"));
const parser = new Parser();
parser.setLanguage(language);
if (parser.parse('exec 3<>"$f"\n').rootNode.hasError) die("fork built but does not parse a patched construct");
log("fork is live — verify with: node lib/grammar/test.js");
