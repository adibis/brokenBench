#!/usr/bin/env python3
"""Verify every exercise fails in its shipped (unpatched) state.

Catches an exercise that was accidentally committed already-fixed, or a
checker that doesn't actually test anything and would pass regardless of
the bug. A compile error counts as a fail here too (several learn/
exercises' bug *is* a compile error, by design; unique_scalar_vs_slice's
patched build crashes at compile, so its unpatched skeleton failing here
just needs to not accidentally pass, same as any other exercise).

Reads the exercise list from manifest.toml (via find_exercise.py), not a
directory glob -- the manifest is what defines "every exercise that needs
to pass/fail," independent of how exercises/ happens to be laid out on
disk (single files today, domain subdirectories, someday maybe multi-file
directories too).
"""

import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(__file__), "..")
FIND_EXERCISE = os.path.join(os.path.dirname(__file__), "find_exercise.py")
VFLAGS = ["--binary", "--timing", "-j", "0", "-Wno-fatal", "-Wno-IMPLICITSTATIC"]

COMPILE_TIMEOUT_S = 60
# Verilator's SMT-backed constrained-random path solves bit-by-bit over a
# single long-lived z3 session, not natively -- even a trivial range
# constraint goes through hundreds of interactive solver queries per
# randomize() call. That's cheap once, but a couple of exercises call
# randomize() in a 10-20k iteration statistics-gathering loop
# (off_by_one_excludes_boundary, dist_weight_operator), which adds up to
# real seconds even locally (~7-14s on this machine) and measurably more
# on CI's containerized runner. 120s leaves real margin above that
# observed worst case while still catching a genuine hang (the original
# bug: an unbounded z3 UNSAT proof on a contradictory constraint set once
# hung a CI run for 15+ minutes with no output at all).
SIM_TIMEOUT_S = 120
# z3's own per-call timeout is a second, independent safety net: it bounds
# any single query, so a pathological one can't eat the whole SIM_TIMEOUT_S
# budget by itself. Verilator treats a solver timeout as "couldn't solve,"
# i.e. randomize() returns 0 -- the correct outcome for a genuinely
# unsatisfiable constraint anyway.
SIM_ENV = dict(os.environ, VERILATOR_SOLVER="z3 -t:10000 --in")


def all_exercises():
    result = subprocess.run([sys.executable, FIND_EXERCISE, "--json"],
                             capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def run_one(sv_path):
    name = os.path.splitext(os.path.basename(sv_path))[0]
    with tempfile.TemporaryDirectory() as builddir:
        try:
            compile_result = subprocess.run(
                ["verilator"] + VFLAGS + [sv_path, "--top-module", "top", "-o", "sim",
                                           "-Mdir", builddir],
                capture_output=True, text=True, timeout=COMPILE_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return name, False, f"COMPILE TIMED OUT after {COMPILE_TIMEOUT_S}s"
        if compile_result.returncode != 0:
            return name, True, "compile error"
        try:
            sim_result = subprocess.run([os.path.join(builddir, "sim")],
                                         capture_output=True, text=True,
                                         env=SIM_ENV, timeout=SIM_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            return name, False, f"TIMED OUT after {SIM_TIMEOUT_S}s -- unbounded solve or infinite loop"
        passed = sim_result.returncode == 0 and "PASS:" in sim_result.stdout
        return name, not passed, ("compile+run, correctly failed" if not passed
                                   else "ALREADY PASSES UNPATCHED")


def main():
    problems = []
    entries = all_exercises()
    for e in entries:
        sv_path = os.path.join(ROOT, e["path"])
        name, ok, detail = run_one(sv_path)
        status = "fails as expected" if ok else "*** PROBLEM ***"
        print(f"{name}: {status} ({detail})", flush=True)
        if not ok:
            problems.append(name)

    print()
    if problems:
        print(f"FAIL: {len(problems)} exercise(s) have a problem in their shipped state "
              f"(see details above -- either already passing, or timed out): "
              f"{', '.join(problems)}", file=sys.stderr)
        sys.exit(1)
    print(f"all {len(entries)} exercises correctly fail in their shipped state")


if __name__ == "__main__":
    main()
