#!/usr/bin/env python3
"""Apply every solution patch into a scratch copy and verify each one passes.

This is how a claimed solution patch is proven genuine: a patch that
doesn't make its own exercise's checker pass is worse than useless. Also
verifies every manifest entry either has a patch file or is explicitly
excluded with a documented reason (requires_patched_verilator +
verilator_broken_as_of) -- an exercise silently missing both would be a
real gap, not something to let through quietly.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(__file__), "..")
FIND_EXERCISE = os.path.join(os.path.dirname(__file__), "find_exercise.py")
PATCH_ALL = os.path.join(os.path.dirname(__file__), "patch_all.py")
VFLAGS = ["--binary", "--timing", "-j", "0", "-Wno-fatal", "-Wno-IMPLICITSTATIC"]

COMPILE_TIMEOUT_S = 60
# See check_unpatched_fails.py's SIM_TIMEOUT_S/SIM_ENV comments -- the
# 10-20k iteration statistics-gathering exercises are genuinely slow via
# Verilator's bit-by-bit SMT solve, patched or not (being satisfiable
# doesn't make the per-iteration solver walk any cheaper, only the
# iteration count does), so this needs the same generous timeout, not a
# tighter one.
SIM_TIMEOUT_S = 120
SIM_ENV = dict(os.environ, VERILATOR_SOLVER="z3 -t:10000 --in")


def all_exercises():
    result = subprocess.run([sys.executable, FIND_EXERCISE, "--json"],
                             capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def main():
    problems = []
    entries = all_exercises()

    for e in entries:
        patch_path = os.path.join(ROOT, "patches", f"{e['slug']}.patch")
        has_patch = os.path.exists(patch_path)
        excluded = e.get("requires_patched_verilator", False)
        if excluded and not e.get("verilator_broken_as_of"):
            problems.append(f"{e['slug']}: requires_patched_verilator=true but no "
                             f"verilator_broken_as_of recorded -- undocumented exclusion")
        if not has_patch and not excluded:
            problems.append(f"{e['slug']}: no patch file and not excluded in manifest.toml")

    if problems:
        for p in problems:
            print(f"MANIFEST/PATCH PROBLEM: {p}", file=sys.stderr)
        sys.exit(1)

    with tempfile.TemporaryDirectory() as scratch:
        shutil.copytree(os.path.join(ROOT, "learn"), os.path.join(scratch, "learn"))
        shutil.copytree(os.path.join(ROOT, "exercises"), os.path.join(scratch, "exercises"))

        patch_result = subprocess.run(
            [sys.executable, PATCH_ALL, "--target-dir", scratch],
            capture_output=True, text=True)
        print(patch_result.stdout)
        if patch_result.returncode != 0:
            print(patch_result.stderr, file=sys.stderr)
            sys.exit(1)

        failures = []
        for e in entries:
            if e.get("requires_patched_verilator"):
                continue
            sv_path = os.path.join(scratch, e["path"])
            with tempfile.TemporaryDirectory() as builddir:
                try:
                    compile_result = subprocess.run(
                        ["verilator"] + VFLAGS + [sv_path, "--top-module", "top", "-o", "sim",
                                                   "-Mdir", builddir],
                        capture_output=True, text=True, timeout=COMPILE_TIMEOUT_S)
                except subprocess.TimeoutExpired:
                    failures.append(f"{e['slug']}: compile timed out after {COMPILE_TIMEOUT_S}s")
                    continue
                if compile_result.returncode != 0:
                    failures.append(f"{e['slug']}: patched version fails to compile:\n"
                                     f"{compile_result.stdout}{compile_result.stderr}")
                    continue
                try:
                    sim_result = subprocess.run([os.path.join(builddir, "sim")],
                                                 capture_output=True, text=True,
                                                 env=SIM_ENV, timeout=SIM_TIMEOUT_S)
                except subprocess.TimeoutExpired:
                    failures.append(f"{e['slug']}: sim timed out after {SIM_TIMEOUT_S}s "
                                     f"-- unbounded solve or infinite loop")
                    continue
                if sim_result.returncode != 0 or "PASS:" not in sim_result.stdout:
                    failures.append(f"{e['slug']}: patched version does not pass its checker:\n"
                                     f"{sim_result.stdout}")
                else:
                    print(f"{e['slug']}: patched, PASS", flush=True)

    if failures:
        for f in failures:
            print(f"PATCH DOES NOT SOLVE: {f}", file=sys.stderr)
        sys.exit(1)

    verifiable = [e for e in entries if not e.get("requires_patched_verilator")]
    excluded = [e for e in entries if e.get("requires_patched_verilator")]
    print()
    print(f"all {len(verifiable)} verifiable patches apply safely and pass their checker")
    if excluded:
        print(f"excluded (documented, not silently skipped): "
              f"{', '.join(e['slug'] for e in excluded)}")


if __name__ == "__main__":
    main()
