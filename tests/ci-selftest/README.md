# ci-selftest

Not exercises. This directory proves the checker scripts in `../../scripts/`
would actually catch a bad exercise or a bad patch, using fixtures built to be
wrong on purpose -- a vacuous checker that always passes, a patch that edits
the checker itself, a patch that applies cleanly but doesn't fix the bug,
manifest drift in both directions -- plus one genuinely correct
exercise+patch pair as a positive control, so a checker script that started
rejecting *everything* would get caught too, not just one that stopped
rejecting anything.

Every real CI gate (`unpatched-must-fail`, `patches-solve`,
`manifest-sync`) only ever runs against the 33 real exercises. That proves
those 33 are fine; it doesn't prove the checking logic itself is still
correct if someone changes `scripts/check_*.py`. This does.

`run_selftest.py` never reimplements the checking logic -- it builds
isolated scratch copies of `scripts/` plus a synthetic `manifest.toml` and
runs the real, unmodified scripts against the fixtures here, asserting the
expected accept/reject outcome. Never touches the real `manifest.toml`,
`learn/`, `exercises/`, or `patches/`.

```bash
make selftest                                    # both groups
python3 tests/ci-selftest/run_selftest.py --group no-verilator
python3 tests/ci-selftest/run_selftest.py --group verilator
```

Run this after changing anything in `scripts/*.py` -- CI runs it on every
push too (`checker-selftest` / `checker-selftest-verilator`), but finding
out locally is faster than finding out from a CI log.
