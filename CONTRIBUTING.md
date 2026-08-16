# Contributing

## Contributing an exercise

Every exercise ships broken, on purpose, with a checker that proves whether
it's fixed. A new exercise contribution is a bug, not a lesson: pick a
mistake that actually shows up in real SystemVerilog or UVM code, write the
class/module that has it, and write a checker that fails unambiguously on
the unpatched version and passes unambiguously once it's fixed.

**Structure of a contribution:**

- The exercise file itself (`learn/<slug>.sv` or
  `exercises/<track>/<slug>.sv`), shipped in its *broken* state -- this is
  what gets committed to the repo directly.
- A `// ---8<--- checker below: don't edit ---` marker separating the buggy
  code from the checker. Everything below the marker must compile and run
  correctly against a *fixed* version of the code above it, and must fail
  loudly (`$fatal`, nonzero exit) against the broken version as shipped.
- A `patches/<slug>.patch` -- a unified diff (`diff -u`) from the broken
  file to a working one, same mechanism
  [ziglings uses](https://codeberg.org/ziglings/exercises/src/branch/main/patches).
  Never commit a solved `.sv` file directly; the patch is the only place a
  solution exists in the repo.
- A `manifest.toml` entry: `slug`, `path`, `order` within its track,
  `track`, and `tags`.

Build the fix first, as a real working reference, outside the repo (a
scratch directory is fine) -- then decide what to strip out of it to make
the broken starting state. That working reference never gets committed
here, even temporarily; `diff -u` against it to produce the patch, then
discard it.

**Before opening a PR:**

- `python3 scripts/check_patch_safety.py patches/<slug>.patch <path>.sv`
  -- confirms your patch doesn't touch anything at or below the checker
  marker. A patch that edits the checker to force a pass is worse than no
  patch, and this is a hard CI gate, not a suggestion.
- `python3 scripts/check_unpatched_fails.py` -- confirms the exercise
  actually fails as shipped.
- `python3 scripts/patch_one.py <slug>` against a scratch copy, then
  re-run the exercise, to confirm your patch actually produces a passing
  fix.
- `python3 scripts/check_manifest_sync.py` -- confirms your `manifest.toml`
  entry matches the file on disk.
- Line length: 100 columns, enforced by `verible-verilog-lint` in CI. No
  other verible style rules apply -- this repo's exercises deliberately
  don't follow verible's default naming/casting conventions (every exercise
  uses `module top;`, for one, so the Makefile can invoke any of them
  uniformly).

All four of those are exactly what CI runs on every push and PR (see
[README.md's "CI and the patch system"](README.md#ci-and-the-patch-system))
-- running them locally first just means you find out before CI does.

## Filing a bug

A good bug report here almost always has one of three shapes:

**An exercise's checker doesn't actually test what it claims to.** Say
which exercise, what you changed, and why the checker still passed (or
still failed) when it shouldn't have. If you can trigger
`scripts/check_unpatched_fails.py` or `scripts/check_patches_pass.py`
failing locally, include that output -- it's the fastest way to reproduce.

**A Verilator version mismatch.** This repo pins `verilator/verilator:v5.050`
in CI and is developed against a matching local build. If an exercise
behaves differently on your Verilator version -- compiles when it shouldn't,
a constraint solves differently, timing/randomization differs -- include
`verilator --version`, the exercise slug, and the actual vs. expected
output. Check `manifest.toml` first: a handful of exercises track known
version-specific behavior there (`requires_patched_verilator`,
`verilator_broken_as_of`) and may already be a documented gap rather than a
new bug.

**Something in the patch/CI mechanics is broken** -- `make check` mis-orders
a track, `find_exercise.py` can't resolve a slug that's in `manifest.toml`,
a patch that should apply cleanly doesn't. Include the exact command and
its full output.

In all three cases: exercise slug, exact command run, full output (not a
paraphrase), and your Verilator version. If it's a claim that an exercise
is broken, "I think this should pass/fail and it doesn't" plus the command
that shows it is enough -- you don't need to diagnose the root cause
yourself.
