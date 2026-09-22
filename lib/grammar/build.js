#!/usr/bin/env node

/**
 * Build BashTab's forked tree-sitter-bash parser.
 *
 *   node lib/grammar/build.js          # stage, patch, generate, compile
 *   node lib/grammar/build.js --check  # verify patches still apply; no build
 *
 * The fork is staged into lib/grammar/build/ (gitignored) from the installed
 * upstream package, so nothing generated is committed: only patches.js is.
 * Rebasing onto a new tree-sitter-bash is `pnpm update` + re-run this script;
 * if an anchor no longer matches, the build fails and names the patch.
 *
 * Requires a C toolchain. When the fork is absent or stale, every consumer
 * falls back to the stock parser (see load.js), so this build is optional.
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const ROOT = path.resolve(__dirname, "..", "..");
const UPSTREAM = path.join(ROOT, "node_modules", "tree-sitter-bash");
const STAGE = path.join(__dirname, "build");
const TS_CLI = path.join(ROOT, "node_modules", ".bin", "tree-sitter");
const PATCHES = require("./patches.js");

const checkOnly = process.argv.includes("--check");
const log = (m) => process.stderr.write(`bu grammar: ${m}\n`);

function die(message) {
    process.stderr.write(`bu grammar: ${message}\n`);
    process.exit(1);
}

if (!fs.existsSync(UPSTREAM)) die(`tree-sitter-bash is not installed. Run 'pnpm install' in ${ROOT}.`);

// ── 1. apply patches to upstream grammar.js ──────────────────────────────
const upstreamGrammar = fs.readFileSync(path.join(UPSTREAM, "grammar.js"), "utf8");
let patched = upstreamGrammar;
for (const p of PATCHES) {
    const hits = patched.split(p.find).length - 1;
    if (hits === 0) {
        die(
            `patch '${p.id}' no longer applies — upstream changed the code it anchors on.\n` +
                `  ${p.summary}\n` +
                `  Update the 'find' string in lib/grammar/patches.js, or drop the patch if\n` +
                `  upstream has fixed it (check with: node lib/grammar/test.js).`
        );
    }
    if (hits > 1) die(`patch '${p.id}' anchor is ambiguous (${hits} matches) — make it more specific.`);
    patched = patched.replace(p.find, p.replace);
}
log(`${PATCHES.length} patches apply cleanly against tree-sitter-bash ${require(path.join(UPSTREAM, "package.json")).version}`);
if (checkOnly) process.exit(0);

// ── 2. stage a buildable copy ────────────────────────────────────────────
fs.rmSync(STAGE, { recursive: true, force: true });
fs.mkdirSync(STAGE, { recursive: true });
for (const entry of ["bindings", "binding.gyp", "package.json", "tree-sitter.json"]) {
    fs.cpSync(path.join(UPSTREAM, entry), path.join(STAGE, entry), { recursive: true });
}
// scanner.c and the tree_sitter headers come over untouched; parser.c is
// regenerated, so the stale upstream copy must not be carried across.
fs.mkdirSync(path.join(STAGE, "src"), { recursive: true });
fs.cpSync(path.join(UPSTREAM, "src", "scanner.c"), path.join(STAGE, "src", "scanner.c"));
fs.cpSync(path.join(UPSTREAM, "src", "tree_sitter"), path.join(STAGE, "src", "tree_sitter"), { recursive: true });
fs.writeFileSync(path.join(STAGE, "grammar.js"), patched);
// node-gyp needs node-addon-api, which lives in the repo's node_modules.
const link = path.join(STAGE, "node_modules");
if (!fs.existsSync(link)) fs.symlinkSync(path.join(ROOT, "node_modules"), link, "dir");
log("staged into lib/grammar/build/");

// ── 3. generate + compile ────────────────────────────────────────────────
const run = (cmd, args) => {
    try {
        execFileSync(cmd, args, { cwd: STAGE, stdio: ["ignore", "ignore", "pipe"] });
    } catch (e) {
        const detail = (e.stderr || Buffer.from("")).toString().trim().split("\n").slice(0, 12).join("\n");
        die(`${path.basename(cmd)} failed:\n${detail}`);
    }
};

if (!fs.existsSync(TS_CLI)) die("tree-sitter CLI not found — is tree-sitter-cli installed?");
run(TS_CLI, ["generate"]);
log("parser generated");

// node-gyp is not a dependency of this repo: prefer a locally installed one,
// otherwise let npx fetch it (first build only, needs network).
const localGyp = path.join(ROOT, "node_modules", ".bin", "node-gyp");
if (fs.existsSync(localGyp)) {
    run(localGyp, ["rebuild"]);
} else {
    log("node-gyp not installed locally — fetching via npx");
    run("npx", ["--yes", "node-gyp", "rebuild"]);
}
log("parser compiled");

// ── 4. prove it loads and actually fixes something ───────────────────────
const { load } = require("./load.js");
const { language, forked } = load({ force: true });
if (!forked) die("built the fork but could not load it");
const Parser = require(path.join(ROOT, "node_modules", "tree-sitter"));
const parser = new Parser();
parser.setLanguage(language);
if (parser.parse('exec 3<>"$f"\n').rootNode.hasError) die("fork built but does not parse a patched construct");
log("fork is live — run 'node lib/grammar/test.js' for the full corpus and regression sweep");
