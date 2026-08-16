#!/usr/bin/env python3
"""Apply one exercise's solution patch, safely.

usage: patch_one.py <slug> [--target-dir DIR]

Resolves the slug via manifest.toml, refuses to apply if the patch doesn't
apply cleanly (patch --dry-run) or if it would touch anything at/below
the checker marker (see check_patch_safety.py -- both checks run before
anything on disk is touched). Applies in place by default; --target-dir
lets CI apply into a scratch copy of the repo instead of the real tree.
Uses `patch -p1`, not `git apply`, so --target-dir works for a plain
directory too, not just a git worktree.
"""

import argparse
import json
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
FIND_EXERCISE = os.path.join(os.path.dirname(__file__), "find_exercise.py")
CHECK_SAFETY = os.path.join(os.path.dirname(__file__), "check_patch_safety.py")


def resolve(slug):
    result = subprocess.run(
        [sys.executable, FIND_EXERCISE, "--slug", slug, "--json"],
        capture_output=True, text=True)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("slug")
    parser.add_argument("--target-dir", default=ROOT,
                         help="repo root to apply into (default: the real repo)")
    parser.add_argument("--allow-unverifiable", action="store_true",
                         help="apply even if the exercise is flagged "
                              "requires_patched_verilator in manifest.toml")
    args = parser.parse_args()

    entry = resolve(args.slug)
    if entry.get("requires_patched_verilator") and not args.allow_unverifiable:
        print(f"{args.slug}: manifest.toml marks this requires_patched_verilator=true "
              f"(broken as of Verilator {entry.get('verilator_broken_as_of', '?')}) -- "
              f"applying its patch can't be verified on a stock toolchain. "
              f"Pass --allow-unverifiable to apply anyway.", file=sys.stderr)
        sys.exit(1)

    patch_path = os.path.join(ROOT, "patches", f"{args.slug}.patch")
    if not os.path.exists(patch_path):
        print(f"no patch file at {patch_path}", file=sys.stderr)
        sys.exit(1)

    target_path = os.path.join(args.target_dir, entry["path"])

    safety = subprocess.run(
        [sys.executable, CHECK_SAFETY, patch_path, target_path],
        capture_output=True, text=True)
    if safety.returncode != 0:
        print(safety.stderr, file=sys.stderr)
        sys.exit(1)

    check = subprocess.run(
        ["patch", "-p1", "-d", args.target_dir, "--dry-run", "-i", os.path.abspath(patch_path)],
        capture_output=True, text=True)
    if check.returncode != 0:
        print(f"{args.slug}: patch does not apply cleanly:\n{check.stdout}{check.stderr}",
              file=sys.stderr)
        sys.exit(1)

    apply = subprocess.run(
        ["patch", "-p1", "-d", args.target_dir, "-i", os.path.abspath(patch_path)],
        capture_output=True, text=True)
    if apply.returncode != 0:
        print(f"{args.slug}: patch failed after passing --dry-run (unexpected):\n"
              f"{apply.stdout}{apply.stderr}", file=sys.stderr)
        sys.exit(1)

    print(f"{args.slug}: patched {entry['path']}")


if __name__ == "__main__":
    main()
