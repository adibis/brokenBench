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


def all_exercises():
    result = subprocess.run([sys.executable, FIND_EXERCISE, "--json"],
                             capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else []


def run_one(sv_path):
    name = os.path.splitext(os.path.basename(sv_path))[0]
    with tempfile.TemporaryDirectory() as builddir:
        compile_result = subprocess.run(
            ["verilator"] + VFLAGS + [sv_path, "--top-module", "top", "-o", "sim",
                                       "-Mdir", builddir],
            capture_output=True, text=True)
        if compile_result.returncode != 0:
            return name, True, "compile error"
        sim_result = subprocess.run([os.path.join(builddir, "sim")],
                                     capture_output=True, text=True)
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
        print(f"{name}: {status} ({detail})")
        if not ok:
            problems.append(name)

    print()
    if problems:
        print(f"FAIL: {len(problems)} exercise(s) don't fail unpatched: {', '.join(problems)}",
              file=sys.stderr)
        sys.exit(1)
    print(f"all {len(entries)} exercises correctly fail in their shipped state")


if __name__ == "__main__":
    main()
