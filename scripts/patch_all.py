#!/usr/bin/env python3
"""Apply every exercise's solution patch, safely, stopping at the first failure.

usage: patch_all.py [--target-dir DIR] [--include-unverifiable]

Thin driver over patch_one.py -- every safety/apply check it does runs here
too, per exercise. Exercises flagged requires_patched_verilator in
manifest.toml are skipped by default (reported, not silently dropped) since
applying a patch nobody can verify passes is worse than not applying it;
pass --include-unverifiable to apply those too (e.g. the advisory CI job
that builds a patched Verilator separately).
"""

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
FIND_EXERCISE = os.path.join(os.path.dirname(__file__), "find_exercise.py")
PATCH_ONE = os.path.join(os.path.dirname(__file__), "patch_one.py")


def all_exercises():
    result = subprocess.run([sys.executable, FIND_EXERCISE, "--json"],
                             capture_output=True, text=True)
    return json.loads(result.stdout) if result.returncode == 0 else []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-dir", default=ROOT)
    parser.add_argument("--include-unverifiable", action="store_true")
    args = parser.parse_args()

    patched, skipped, failed = [], [], []

    for entry in all_exercises():
        slug = entry["slug"]
        patch_path = os.path.join(ROOT, "patches", f"{slug}.patch")
        if not os.path.exists(patch_path):
            failed.append((slug, "no patch file in patches/"))
            continue
        if entry.get("requires_patched_verilator") and not args.include_unverifiable:
            skipped.append(slug)
            continue

        cmd = [sys.executable, PATCH_ONE, slug, "--target-dir", args.target_dir]
        if args.include_unverifiable:
            cmd.append("--allow-unverifiable")
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            failed.append((slug, result.stderr.strip()))
            print(result.stderr, file=sys.stderr)
            break
        patched.append(slug)
        print(result.stdout, end="")

    print()
    print(f"patched: {len(patched)}   skipped (requires_patched_verilator): {len(skipped)}"
          f"   failed: {len(failed)}")
    if skipped:
        print(f"  skipped: {', '.join(skipped)}")
    if failed:
        print(f"  failed: {failed[0][0]}: {failed[0][1]}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
