#!/usr/bin/env python3
"""Verify manifest.toml and the on-disk learn/+exercises/ files agree.

Checks both directions: every manifest entry's path must exist on disk,
and every .sv file on disk must have a manifest entry. This repo already
had a real desync bug once (stale numbers left over from a rename) --
this is the automated version of the sweep that caught it by hand.
"""

import glob
import os
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
FIND_EXERCISE = os.path.join(os.path.dirname(__file__), "find_exercise.py")


def main():
    import json
    result = subprocess.run([sys.executable, FIND_EXERCISE, "--json", "--track", "learn"],
                             capture_output=True, text=True)
    learn = json.loads(result.stdout) if result.returncode == 0 else []
    result = subprocess.run([sys.executable, FIND_EXERCISE, "--json", "--track", "exercises"],
                             capture_output=True, text=True)
    exercises = json.loads(result.stdout) if result.returncode == 0 else []
    manifest_paths = {e["path"] for e in learn + exercises}

    disk_paths = set()
    for pattern in ("learn/*.sv", "exercises/*.sv"):
        for p in glob.glob(os.path.join(ROOT, pattern)):
            disk_paths.add(os.path.relpath(p, ROOT))

    missing_on_disk = manifest_paths - disk_paths
    missing_in_manifest = disk_paths - manifest_paths

    problems = []
    for p in sorted(missing_on_disk):
        problems.append(f"manifest.toml references '{p}' but it doesn't exist on disk")
    for p in sorted(missing_in_manifest):
        problems.append(f"'{p}' exists on disk but has no manifest.toml entry")

    if problems:
        for p in problems:
            print(f"SYNC ERROR: {p}", file=sys.stderr)
        sys.exit(1)

    print(f"manifest.toml in sync with disk: {len(manifest_paths)} exercises, both directions")


if __name__ == "__main__":
    main()
