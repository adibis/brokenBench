#!/usr/bin/env python3
"""Verify every exercise fails in its shipped (unpatched) state.

Catches an exercise that was accidentally committed already-fixed, or a
checker that doesn't actually test anything and would pass regardless of
the bug. A compile error counts as a fail here too (several learn/
exercises' bug *is* a compile error, by design; unique_scalar_vs_slice's
patched build crashes at compile, so its unpatched skeleton failing here
just needs to not accidentally pass, same as any other exercise).
"""

import glob
import os
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(__file__), "..")
VFLAGS = ["--binary", "--timing", "-j", "0", "-Wno-fatal", "-Wno-IMPLICITSTATIC"]


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
    svs = sorted(glob.glob(os.path.join(ROOT, "learn", "*.sv"))
                 + glob.glob(os.path.join(ROOT, "exercises", "*.sv")))
    for sv in svs:
        name, ok, detail = run_one(sv)
        status = "fails as expected" if ok else "*** PROBLEM ***"
        print(f"{name}: {status} ({detail})")
        if not ok:
            problems.append(name)

    print()
    if problems:
        print(f"FAIL: {len(problems)} exercise(s) don't fail unpatched: {', '.join(problems)}",
              file=sys.stderr)
        sys.exit(1)
    print(f"all {len(svs)} exercises correctly fail in their shipped state")


if __name__ == "__main__":
    main()
