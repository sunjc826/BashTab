# BashTab's tree-sitter-bash fork

`tree-sitter-bash` rejects a number of constructs that are **valid bash** —
`bash -n` accepts every repro in `corpus/causes/`. Those gaps cost BashTab
twice:

* **Completion** (`lib/bin/bu_ts_daemon.js`) parses command lines the user
  types. Nothing in this repo can be rewritten to fix that.
* **Linting** (`lib/lint/bu_lint.js`) skips rules inside regions it cannot
  parse, and reports the gap as `BU000`.

This directory carries a small patch set against the installed upstream
grammar, plus the build and the checks that keep it honest.

## Layout

| Path | |
|---|---|
| `vendor/` | **The fork.** Committed: `grammar.js` (patched), `src/scanner.c`, the binding boilerplate, and `PROVENANCE.json` |
| `patches.js` | How `vendor/grammar.js` is derived from upstream. Not applied at build time — it is the record `--check` and `--rebase` use |
| `build.js` | Compile `vendor/` into `out/`; also `--check` and `--rebase` |
| `load.js` | Resolve the fork if built, else stock. Every consumer goes through this |
| `corpus/causes/` | One repro per known gap, each marked `# expect: fixed` or `# expect: unfixed` |
| `corpus/regression/` | Constructs that must keep parsing |
| `test.js` | Regression sweep + cause expectations + `bash -n` validity |
| `out/` | Generated: `parser.c`, the compiled addon. Gitignored |

## Using it

```sh
node lib/grammar/build.js           # compile vendor/ into out/
node lib/grammar/test.js            # regression sweep + cause expectations
node lib/grammar/build.js --check   # vendored == upstream + patches?
node lib/grammar/build.js --rebase  # re-derive vendor/ from current upstream
```

The grammar is edited through `patches.js`, not by hand: `--check` fails if
`vendor/grammar.js` stops matching upstream + the patch set, so a hand edit is
caught rather than quietly becoming untracked divergence. `src/scanner.c` is
vendored too and *may* be edited directly — two unfixed causes need it — but
`--check` reports when it diverges from upstream so the divergence stays
deliberate.

## Dependencies

**Using BashTab: nothing new.** The fork is optional. `load.js` falls back to
the stock parser, and the linter reports the gaps as `BU000` instead.

**Building the fork** additionally needs:

| | |
|---|---|
| C/C++ toolchain | `gcc`/`g++` or `clang`, plus `make` — compiles `parser.c`, `scanner.c`, `binding.cc` |
| Python 3 | required by `node-gyp` (gyp is a Python program) |
| Node.js + `pnpm install` | already needed for the tree-sitter daemon and Fig spec conversion |

`node-gyp` is a normal dependency (pinned exactly), so `pnpm install` provides
it and building needs no network. `tree-sitter-cli` (also pinned) is a prebuilt
binary and needs no toolchain of its own. Only the C toolchain and Python 3 are
system-level — install those with your package manager. Vendoring also *dropped* one dependency: upstream's
`bindings/node/index.js` pulls in `node-gyp-build`, which the vendored fork
does not use — `load.js` requires the compiled addon directly.

The fork is **optional**. Without it, `load.js` falls back to the stock parser
and everything still works — the linter just reports more `BU000` coverage
warnings. Nothing requires a toolchain unless you choose to build.

## Current state

4 of 11 known causes are fixed: `<>` redirects, `$((10#$var))`, nested
subscripts, and ternary subscript indices. The other seven are documented in
`corpus/causes/` with the reason each was left alone. The sweep reports
**0 regressions** across every shell script in the repo.

## Adding a patch

1. Add the repro to `corpus/causes/`, marked `# expect: unfixed`, and confirm
   `bash -n` accepts it. If bash rejects it, it is not a grammar bug.
2. Add the patch to `patches.js` with an anchor specific enough to match once.
3. `node lib/grammar/build.js && node lib/grammar/test.js`.
4. Flip the marker to `# expect: fixed` once it passes.

**Run the sweep before believing a patch.** During development, a one-line
addition of `$.subscript` to the C-style `for()` expression language looked
obviously correct, fixed its repro, and silently broke
`for ((i=0; i<3; i++))` — the most common loop in the language. Only the
regression sweep caught it. That patch was reverted; see
`corpus/causes/05_for_header_subscript.sh`.

Prefer `grammar.js` over `src/scanner.c`. This fork does not touch the
external scanner, which keeps rebasing a `grammar.js`-only exercise. Two of
the unfixed causes (01, 11) need scanner work and were left for that reason.

## Rebasing onto a new tree-sitter-bash

`pnpm update tree-sitter-bash`, then `node lib/grammar/build.js`. If upstream
changed the code a patch anchors on, the build fails and names the patch
rather than silently producing an unpatched parser. If upstream has fixed a
cause outright, `test.js` reports the repro as "marked unfixed but now
parses" so the patch can be dropped.
