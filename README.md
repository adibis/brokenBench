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

## Quickstart

```bash
brew install verilator          # or see Requirements below for your platform
git clone https://github.com/adibis/brokenBenchPrivate.git brokenbench && cd brokenbench
make run EX=sv_mechanics_chain
```

That compiles and runs one exercise. It'll fail -- open
`learn/sv_mechanics_chain.sv`, write the constraints the comment above the
checker marker asks for, and run the same command again until it prints
`PASS`. Then `make list` to see everything else.

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

- [Verilator](https://verilator.org/guide/latest/install.html), free and
  open source. No simulator license, no signup.
  ```bash
  brew install verilator     # macOS
  # or see the Verilator install guide for your platform
  ```
- Python 3 (any reasonably modern version -- `scripts/find_exercise.py`'s
  manifest parser is hand-rolled specifically to avoid needing 3.11+ or a
  third-party package).
- `patch` (GNU patch), for `scripts/patch_one.py`/`patch_all.py`. Usually
  preinstalled on macOS and Linux.
- [`verible-verilog-format`](https://github.com/chipsalliance/verible)
  (part of the verible release bundle), only needed for `make format` /
  `make format-check` -- not required just to run exercises.

## Running exercises

Exercises are referred to by a stable slug (the filename, minus `.sv`), not
a number -- `manifest.toml` is the one place that tracks each exercise's
track, order, and tags, so exercises can be reordered or retagged without
ever renaming a file or breaking a command you've already got memorized.

**Browse what's available:**

```bash
make list                              # every exercise in every track, with tags
make find TAG=multi-constraint         # exercises tagged with a specific gotcha
make find TAG=tool-limitation TRACK=sv # narrow a tag search to one track
```

**Work one exercise at a time:**

```bash
make run EX=dist_coin_and_die
make run EX=command_stream_bandwidth_cap
```

**Work through a whole track in order**, stopping at the first failure --
the rustlings-style "keep running the same command" loop:

```bash
make check TRACK=learn
make check TRACK=sv
make check TRACK=sv EX=thermal_power_fuzzer      # resume partway through
```

`TRACK` is one of `learn`, `sv`, `uvm`, `csr` -- matching `manifest.toml`'s
`track` field for each exercise, not the directory layout directly (`sv`,
`uvm`, and `csr` all nest under `exercises/` on disk purely for browsing;
the manifest is what `make check`/`make find` actually key off).

**Clean up build artifacts** (compiled sim binaries under `.build/`):

```bash
make clean
```

Fix the class or function at the top of whichever exercise file you're stuck
on -- never touch anything at or below the `// ---8<--- checker below: don't
edit ---` marker, that part is correct as given and is what's judging you.
Re-run `make run EX=...` after every change until it prints `PASS`.

Output is colorized (red for failures, green for pass) and respects
[`NO_COLOR`](https://no-color.org/) if your terminal or pipe doesn't want
escape codes.

## Contributing

A contribution is a new broken exercise: the bug itself, a checker that
fails unambiguously as shipped and passes unambiguously once fixed, and a
`patches/<slug>.patch` diff that proves the fix works -- never a solved
`.sv` file committed directly. See [CONTRIBUTING.md](CONTRIBUTING.md) for
the full file structure, the authoring method (solve it first, outside the
repo, then decide what to strip out), and the checklist to run before
opening a PR.

## Filing bugs

Most bug reports here are one of three things: a checker that doesn't
actually test what it claims to, an exercise that behaves differently on
your Verilator version than the one this repo is pinned to, or something
broken in the patch/CI mechanics themselves. See
[CONTRIBUTING.md](CONTRIBUTING.md#filing-a-bug) for what to include in
each case.

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

- **lint** -- formatting checked directly against shipped files with
  `make format-check` (`verible-verilog-format`), then patches applied
  into a scratch copy and checked against this repo's 100-column
  line-length standard with `verible-verilog-lint`.
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

## Real, current tool limitations found while building this

Known Verilator gaps this repo works around or documents -- not bugs in the
exercises. A few things here aren't textbook gotchas, they're things this
repo's own exercises ran into on the current Verilator toolchain while
being built and validated; worth knowing about if you hit something that
looks like a tooling quirk rather than the intended lesson:

- **`unique{}` on an array is reliable up to about 4 elements and silently
  wrong past that** -- it returns success with actual duplicates present,
  independent of how much headroom exists in the value space. Not built into
  its own exercise; the pairwise-inequality workaround shows up in
  `thermal_power_fuzzer` instead, alongside the row-slice crash below.
- **`unique{}` on a row-slice of a 2D array crashes the compiler outright**
  (an internal fault, not a graceful error) on every released Verilator as
  of this writing. `thermal_power_fuzzer` avoids it entirely and uses
  pairwise inequality instead. A real fix is up for review upstream
  ([verilator/verilator#8100](https://github.com/verilator/verilator/pull/8100));
  `unique_scalar_vs_slice` is written for a Verilator built from
  that patch -- see the note at the top of that file for how to point
  `make run` at a patched binary.
- **A `rand`-sized dynamic array combined with a `.sum()`/`.product()`
  reduction constraint over its own contents never solves**, even with
  explicit `solve ... before` ordering hints. The real fix is pinning the
  array's size, not a smarter ordering hint. Not built into an exercise.
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
  see `tagged_frame_sequence`.
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
  whole-array `!=` to SMT at all, unconditionally. Not built into its own
  exercise; avoid whole-array comparison entirely (compare element by
  element instead).
- **Constraining a dynamic array's `.size()` inside an inline `randomize()
  with {}` block reports success but doesn't actually resize the array** --
  `f.randomize() with { payload.size() == 50; }` returns `ok == 1` while
  `f.payload.size()` stays `0`. The identical constraint written at the
  class level (`constraint c { payload.size() inside {[46:2048]}; }`) works
  correctly. Not built into its own exercise; pin dynamic-array contents by
  assigning elements directly after a normal `randomize()` call instead of
  trying to pin size via an inline `with {}`.
- **A third separate `randomize()` call site for the same class, in the
  same process, can corrupt an *earlier* loop's `pre_randomize()`-set,
  non-rand field value** on Verilator 5.050 -- confirmed with
  `l2_frame_fuzzer`'s checker: two loops, each calling `randomize()` on a
  fresh instance of the same class, work correctly; adding a third,
  otherwise-harmless call site anywhere later in the same `initial` block
  makes the *first* loop's `header` value (set from an external
  `package`-scope flag in `pre_randomize()`) come back stale on every
  iteration. Confirmed absent on a from-source build past that release.
  Not built into its own exercise (the checker routes around it by reusing
  an existing loop's call site instead of adding a third one); if you hit
  a `pre_randomize()`-derived field that looks stale only sometimes, check
  how many distinct `randomize()` call sites exist for that class before
  assuming the constraint logic is wrong.
- **`dist` on an enum-typed `rand` field doesn't distribute correctly**,
  even though identical weights on a plain sized `bit` field of the same
  width work exactly as specified -- confirmed over 2000 trials: an enum
  field with `dist {A:=20, B:=50, C:=30}` lands nowhere near those weights
  (25/28/47 observed), while the same weights on `rand bit [1:0]` land
  within about a point of target (19/51/30). Don't use an enum type for a
  weighted-`dist` field in Verilator -- use a plain sized `bit` field with
  documented numeric meanings instead. Confirmed again inside a larger
  constraint set in `risc_v_forwarding_window`: an isolated `dist` directly
  on the enum landed close to target in a quick check, but combined with
  the rest of that exercise's implications it skewed by several points on
  Homebrew Verilator (35.8%/44.7% against a 40%/40% target) -- reliable
  enough to fool a spot check, not reliable enough to trust. The exercise
  routes around it with a plain-`bit` pick mapped onto the enum afterward.

This list is Verilator-specific gaps only. For general SystemVerilog
language semantics that are just as easy to mistake for a tool bug --
things that are surprising but are simply how the language works -- see
[docs/reference.md](docs/reference.md).

If you hit something that looks like this list rather than the intended
lesson, it's probably exactly that -- see [Filing bugs](#filing-bugs)
rather than assume you did something wrong.

## License

MIT. See [LICENSE](LICENSE). See [CONTRIBUTING.md](CONTRIBUTING.md) if
you're thinking about sending a patch.
