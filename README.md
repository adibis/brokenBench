# brokenbench

Fix tiny broken SystemVerilog testbenches, one at a time, until they pass.

Inspired by [ziglings](https://codeberg.org/ziglings/exercises) and
[rustlings](https://github.com/rust-lang/rustlings): every exercise is a
single self-contained `.sv` file with a real bug in it and a checker at the
bottom that tells you, unambiguously, whether you fixed it. No tutorials, no
multiple choice -- you read real compiler output or a real runtime failure,
figure out what's actually wrong, and fix it.

This isn't generic SystemVerilog trivia. Every exercise here is built around
a mistake that actually shows up in real constrained-random verification
code -- the kind that either won't compile, silently does nothing, or worse,
compiles clean and passes while not actually testing what it looks like it's
testing. That last category is most of `exercises/`, not an afterthought.

Companion to [chipdv.io](https://chipdv.io) -- real DV engineering, worked
all the way through, not tutorials.

## Two tracks

- **`learn/`** -- never touched SystemVerilog before? Start here. Missing
  keywords, `=` vs `==`, an unchecked return value, a null handle. Fast
  feedback loop, one concept per exercise (or a short, deliberate chain of
  them).
- **`exercises/`** -- interview-prep. Every one of these is either a
  documented real-world constrained-random gotcha or something found by
  actually testing this repo's own exercises against Verilator: a range
  constraint that silently narrows to one legal value, `dist` weight
  operators that skew a distribution without erroring, non-overlapping
  address-range generation, 2D matrix constraints, Hamming-distance
  randomization, a genuinely unsatisfiable pair of constraints, and more.

## Requirements

Just [Verilator](https://verilator.org/guide/latest/install.html), free and
open source. No simulator license, no signup, nothing else to install.

```bash
brew install verilator     # macOS
# or see the Verilator install guide for your platform
```

## Running

Exercises are referred to by a stable slug (the filename, minus `.sv`), not
a number -- `manifest.toml` is the one place that tracks each exercise's
track, order, and tags, so exercises can be reordered or retagged without
ever renaming a file or breaking a command you've already got memorized.

```bash
make list                              # see every exercise in both tracks, with tags
make run EX=missing_rand               # compile and run one exercise
make run EX=and_instead_of_implies
make check TRACK=learn                 # run a whole track in order, stop at the first failure
make check TRACK=exercises
make check TRACK=exercises EX=cyclic_rand_constraint   # start partway through a track
make find TAG=multi-constraint         # list exercises with a given tag
make find TAG=tool-limitation TRACK=exercises
```

Fix the class or function at the top of whichever exercise file you're stuck
on -- never touch anything at or below the `// ---8<--- checker below: don't
edit ---` marker, that part is correct as given and is what's judging you.
Re-run `make run EX=...` after every change until it prints `PASS`.

## Real, current tool limitations found while building this

A few things here aren't textbook gotchas, they're things this repo's own
exercises ran into on the current Verilator toolchain while being built and
validated -- worth knowing about if you hit something that looks like a
tooling quirk rather than the intended lesson:

- **`unique{}` on an array is reliable up to about 4 elements and silently
  wrong past that** -- it returns success with actual duplicates present,
  independent of how much headroom exists in the value space. See
  `unique_oversized_array` and its companion, `unique_without_unique_keyword`,
  which shows the pairwise-inequality workaround.
- **`unique{}` on a row-slice of a 2D array crashes the compiler outright**
  (an internal fault, not a graceful error) on every released Verilator as
  of this writing. `matrix_row_col_sum` avoids it entirely and uses
  pairwise inequality instead. A real fix is up for review upstream
  ([verilator/verilator#8100](https://github.com/verilator/verilator/pull/8100));
  `unique_scalar_vs_slice` is written for a Verilator built from
  that patch -- see the note at the top of that file for how to point
  `make run` at a patched binary.
- **A `rand`-sized dynamic array combined with a `.sum()`/`.product()`
  reduction constraint over its own contents never solves**, even with
  explicit `solve ... before` ordering hints. `array_size_before_reduction`
  is built around this directly; the real fix is pinning the array's size,
  not a smarter ordering hint.
- **`randomize(field)` does not hold other `rand` fields as state**, contrary
  to documented LRM behavior for single-variable randomization -- calling
  it re-randomizes the whole object regardless of which field was named.
  Not built into an exercise (there's no reliable way to demonstrate a "fix"
  for behavior that's simply not implemented as documented), but worth
  knowing if you're relying on that semantic.

If you hit something that looks like this list rather than the intended
lesson, it's probably exactly that -- open an issue rather than assume you
did something wrong.

## CI and the patch system

Solutions never live in this repo as full solved files -- only `patches/`,
one unified diff per exercise, applying cleanly on top of the shipped
(broken) `.sv` file to produce a working one. Same approach
[ziglings uses](https://codeberg.org/ziglings/exercises/src/branch/main/patches):
answers generated with `diff -u`, never committed in solved form, so
browsing the repo doesn't spoil an exercise the way a `solutions/` folder
full of finished code would.

`scripts/patch_one.py <slug>` applies one exercise's patch; `scripts/patch_all.py`
applies every one. Both refuse to touch anything at or below the checker
marker (`scripts/check_patch_safety.py` enforces this as a hard gate -- a
"solution" that edits the checker to force a pass would be worse than no
patch at all) and refuse to apply if the patch doesn't cleanly apply in the
first place.

CI (`.github/workflows/ci.yml`) runs on every push and pull request:

- **lint** -- patches applied into a scratch copy, then checked against this
  repo's 100-column line-length standard with `verible-verilog-lint`.
- **manifest-sync** -- `manifest.toml` and the actual `.sv` files on disk
  must agree, both directions.
- **unpatched-must-fail** -- every exercise, shipped as-is, must genuinely
  fail. Catches an exercise accidentally committed pre-fixed, or a checker
  that doesn't actually test anything.
- **patches-solve** -- every patch is applied into a scratch copy and must
  make its own exercise's checker pass. This is how a patch is proven to be
  a real, complete solution, not just a plausible-looking diff.

One exercise, `unique_scalar_vs_slice`, needs a Verilator built from an
unreleased upstream patch to even compile (see `manifest.toml`'s
`requires_patched_verilator` / `verilator_broken_as_of` fields on that
entry -- that's the only place this exclusion is recorded, not hardcoded
into any script). It's excluded from the `patches-solve` gate with a
documented reason rather than silently skipped, and has its own manual-only
CI job as a placeholder for testing it against a patched build once one
exists.

## License

MIT. See [LICENSE](LICENSE).
