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
all the way through, not tutorials. A full multi-file testbench (broken RTL
plus an incomplete environment to finish) is deliberately *not* what this
repo does -- that's a different, bigger kind of challenge, out of scope for
a tool built around single-file, seconds-to-run exercises.

Exercises get written solve-first: build a correct, verified-passing
reference implementation for the pattern, then decide what to strip out to
make a real exercise. That working reference never gets committed here,
even temporarily -- it's authored outside the repo (a scratch directory, or
notes kept alongside the exercise plan) and the repo only ever sees the
broken starting state plus its `patches/` diff, same as every other
exercise.

## Tracks

Two top-level tracks, split by **audience**, not topic:

- **`learn/`** -- never touched SystemVerilog before? Start here. Missing
  keywords, `=` vs `==`, an unchecked return value, a null handle. Fast
  feedback loop, one concept per exercise (or a short, deliberate chain of
  them).
- **`exercises/`** -- interview-prep, organized by domain in subdirectories
  (splitting *this* level by audience wouldn't make sense -- domain is what
  actually changes here, difficulty stays a tag, same as everywhere else in
  this repo):
  - **`exercises/sv/`** -- core SystemVerilog and constrained-random gotchas.
    Every one of these is either a documented real-world gotcha or something
    found by actually testing this repo's own exercises against Verilator: a
    range constraint that silently narrows to one legal value, `dist` weight
    operators that skew a distribution without erroring, non-overlapping
    address-range generation, 2D matrix constraints, Hamming-distance
    randomization, a genuinely unsatisfiable pair of constraints, and more.
  - **`exercises/uvm/`** -- UVM component-level bugs: a broken scoreboard
    comparison, a `uvm_config_db` type/path mismatch, phasing/objection
    issues. (Not yet populated.)
  - **`exercises/csr/`** -- `uvm_reg` / register-map exercises: access-policy
    mistakes, `mirror()` vs `desired()` confusion, predictor gaps. (Not yet
    populated.)

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
make list                              # see every exercise in every track, with tags
make run EX=missing_rand               # compile and run one exercise
make run EX=and_instead_of_implies
make check TRACK=learn                 # run a whole track in order, stop at the first failure
make check TRACK=sv
make check TRACK=sv EX=cyclic_rand_constraint   # start partway through a track
make find TAG=multi-constraint         # list exercises with a given tag
make find TAG=tool-limitation TRACK=sv
```

`TRACK` is one of `learn`, `sv`, `uvm`, `csr` -- matching `manifest.toml`'s
`track` field for each exercise, not the directory layout directly (`sv`,
`uvm`, and `csr` all nest under `exercises/` on disk purely for browsing;
the manifest is what `make check`/`make find` actually key off).

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
- **`randc`'s cyclic no-repeat guarantee holds under a static constraint but
  breaks under a dynamic one** -- excluding a literal value works as
  documented, but excluding the *previous call's* result (e.g. via
  `post_randomize` state) doesn't: repeats of an already-seen value start
  almost immediately (confirmed: call 2 of 40, 16-value domain) instead of
  only after the full domain is exhausted. Use a plain `rand` field plus a
  used-value queue (`inside {}`) for "don't repeat a used ID" instead --
  see `unique_ids_across_calls`.
- **Indexing a non-`rand` array by a `rand` variable inside a constraint
  crashes the SMT solver outright**, not a graceful solve failure --
  `bit used[16]; constraint c { !used[id]; }` (`id` is `rand`) produces
  `select requires 1 arguments, but was provided with 2 arguments` from the
  solver itself. The queue + `inside {}` idiom above avoids this entirely
  and is the pattern to reuse for any "exclude a set of already-used
  values" constraint.
- **Comparing two whole unpacked arrays with `!=` inside a constraint fails
  outright, regardless of any guard around it** -- `constraint c { has_prev
  -> frame != prev_frame; }` produces a solver error (`Sorts (Array ...)
  and (_ BitVec N) are incompatible`) even when `has_prev` is `0`, so the
  guard never gets a chance to short-circuit it; the solver can't translate
  whole-array `!=` to SMT at all, unconditionally. `frame_pixel_diff`
  avoids whole-array comparison entirely.
- **`dist` on an enum-typed `rand` field doesn't distribute correctly**,
  even though identical weights on a plain sized `bit` field of the same
  width work exactly as specified -- confirmed over 2000 trials: an enum
  field with `dist {A:=20, B:=50, C:=30}` lands nowhere near those weights
  (25/28/47 observed), while the same weights on `rand bit [1:0]` land
  within about a point of target (19/51/30). Don't use an enum type for a
  weighted-`dist` field in Verilator -- use a plain sized `bit` field with
  documented numeric meanings instead.

One more thing worth knowing, though it's standard SystemVerilog semantics
(IEEE 1800-2023 6.21), not a Verilator-specific limitation: **a variable
declared inside a loop's `begin...end` block, without the `automatic`
keyword, defaults to *static* lifetime** -- its initializer runs once, not
on every iteration, so it silently accumulates instead of resetting. Looks
exactly like a randomization bug until traced with real debug output.
Declare loop-body-local accumulator variables `automatic`, or declare once
outside the loop and assign (not re-declare) inside it.

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
