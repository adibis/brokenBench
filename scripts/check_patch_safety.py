#!/usr/bin/env python3
"""Verify a patch never touches the checker or anything below it.

A "solution" patch that edits the checker itself (or the marker line) to
force a pass would look like a passing solution while being worthless --
this is the single most dangerous failure mode in the whole patch system,
so it's a hard gate, not advisory.

Doesn't track hunk line-number arithmetic (a first attempt at that got the
line numbers wrong the moment a fix adds lines above the marker, since the
marker's own position shifts down in the patched file too). Instead: apply
the patch to a scratch copy, then compare byte-for-byte, from each file's
own marker line to EOF. If those two tails are identical, nothing at or
below the checker changed, regardless of how much moved above it.
"""

import re
import subprocess
import sys
import tempfile
import os

MARKER = "// ---8<--- checker below: don't edit ---"


def tail_from_marker(path):
    with open(path) as f:
        lines = f.readlines()
    for i, line in enumerate(lines):
        if MARKER in line:
            return "".join(lines[i:])
    return None


def patch_relative_path(patch_path):
    """The path a patch's own '+++ b/...' header names, independent of
    wherever the caller's target file actually lives on disk -- needed so
    `patch -p1` can find the right file inside a fresh scratch directory."""
    with open(patch_path) as f:
        for line in f:
            m = re.match(r'^\+\+\+ b/(.+)$', line)
            if m:
                return m.group(1).split("\t")[0]
    return None


def main():
    if len(sys.argv) != 3:
        print("usage: check_patch_safety.py <patch-file> <target-sv-file>", file=sys.stderr)
        sys.exit(2)
    patch_path, target_path = sys.argv[1], sys.argv[2]

    old_tail = tail_from_marker(target_path)
    if old_tail is None:
        print(f"UNSAFE: {target_path}: no checker marker found -- can't verify safety",
              file=sys.stderr)
        sys.exit(1)

    rel_path = patch_relative_path(patch_path)
    if rel_path is None:
        print(f"UNSAFE: {patch_path}: couldn't find a '+++ b/...' header to determine "
              f"the patched file's path", file=sys.stderr)
        sys.exit(1)

    with tempfile.TemporaryDirectory() as tmp:
        # Use the patch's own recorded relative path (not target_path, which
        # may be absolute/caller-chosen) so `patch -p1`, which strips one
        # leading path component (a/, b/), finds the right file under tmp.
        scratch = os.path.join(tmp, rel_path)
        os.makedirs(os.path.dirname(scratch), exist_ok=True)
        with open(target_path) as src, open(scratch, "w") as dst:
            dst.write(src.read())
        result = subprocess.run(
            ["patch", "-p1", "-d", tmp, "-i", os.path.abspath(patch_path)],
            capture_output=True, text=True)
        if result.returncode != 0:
            print(f"UNSAFE: {patch_path} failed to apply to a scratch copy:\n{result.stderr}",
                  file=sys.stderr)
            sys.exit(1)
        new_tail = tail_from_marker(scratch)

    if new_tail is None:
        print(f"UNSAFE: {patch_path}: patched file has no checker marker at all", file=sys.stderr)
        sys.exit(1)
    if new_tail != old_tail:
        print(f"UNSAFE: {patch_path}: content at/below the checker marker changed", file=sys.stderr)
        sys.exit(1)

    print(f"safe: {patch_path}")


if __name__ == "__main__":
    main()
