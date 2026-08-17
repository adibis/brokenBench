#!/usr/bin/env python3
"""Prove the real checker scripts (scripts/check_*.py) actually reject bad exercises
and patches, and accept good ones -- using deliberately-built fixtures, run through
the real, unmodified scripts, never a reimplementation of their logic (that would
drift from what actually ships). Never touches the real manifest.toml, learn/,
exercises/, or patches/ -- every scenario runs against an isolated scratch copy.
See README.md in this directory for why this exists.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(HERE, "..", "..")
REAL_SCRIPTS = os.path.join(REPO, "scripts")
FIXTURES = os.path.join(HERE, "fixtures")

# Hardcoded, not "however many scenarios happened to run" -- if a scenario silently
# gets skipped (a fixture goes missing, a function returns early on an exception),
# the assertion count comes up short and that's a hard failure, not a quietly
# smaller green run.
EXPECTED_NO_VERILATOR_CHECKS = 6
EXPECTED_VERILATOR_CHECKS = 3


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def assert_that(condition, description, debug_output=""):
    if not condition:
        print(f"SELFTEST FAILURE: {description}", file=sys.stderr)
        if debug_output:
            print(f"--- output ---\n{debug_output}", file=sys.stderr)
        sys.exit(1)
    print(f"ok: {description}")


def new_scratch_root(entries):
    """entries: list of dicts with slug, path, order, track, tags, and optionally
    fixture (filename under fixtures/, copied to <path>) and patch (filename under
    fixtures/, written to patches/<slug>.patch). Copies the real scripts/ in so
    MANIFEST_PATH/ROOT, resolved relative to each script's own location, naturally
    resolve to this scratch root instead of the real repo."""
    root = tempfile.mkdtemp(prefix="selftest-")
    shutil.copytree(REAL_SCRIPTS, os.path.join(root, "scripts"))
    os.makedirs(os.path.join(root, "learn"), exist_ok=True)
    os.makedirs(os.path.join(root, "exercises"), exist_ok=True)
    os.makedirs(os.path.join(root, "patches"), exist_ok=True)

    lines = ["# self-test scratch manifest -- not the real manifest.toml"]
    for e in entries:
        lines.append("")
        lines.append("[[exercise]]")
        lines.append(f'slug  = "{e["slug"]}"')
        lines.append(f'path  = "{e["path"]}"')
        lines.append(f'order = {e.get("order", 1)}')
        lines.append(f'track = "{e.get("track", "learn")}"')
        tags = e.get("tags", [])
        lines.append(f'tags  = [{", ".join(chr(34) + t + chr(34) for t in tags)}]')
        if e.get("fixture"):
            dst = os.path.join(root, e["path"])
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy(os.path.join(FIXTURES, e["fixture"]), dst)
        if e.get("patch"):
            shutil.copy(os.path.join(FIXTURES, e["patch"]),
                        os.path.join(root, "patches", f"{e['slug']}.patch"))
    with open(os.path.join(root, "manifest.toml"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return root


# ---------------------------------------------------------------------------
# No-Verilator scenarios: check_patch_safety.py and check_manifest_sync.py
# never compile anything.
# ---------------------------------------------------------------------------

def scenario_patch_safety():
    target = os.path.join(FIXTURES, "good_exercise.sv")
    check_patch_safety = os.path.join(REAL_SCRIPTS, "check_patch_safety.py")

    r = run([sys.executable, check_patch_safety,
             os.path.join(FIXTURES, "bad_marker.patch"), target])
    assert_that(r.returncode != 0 and "UNSAFE" in r.stderr,
                "check_patch_safety.py rejects a patch that edits the checker",
                r.stdout + r.stderr)

    r = run([sys.executable, check_patch_safety,
             os.path.join(FIXTURES, "good_exercise.patch"), target])
    assert_that(r.returncode == 0 and "safe:" in r.stdout,
                "check_patch_safety.py accepts a genuinely safe patch",
                r.stdout + r.stderr)
    return 2


def scenario_manifest_sync():
    root = new_scratch_root([
        {"slug": "ghost", "path": "learn/ghost.sv", "order": 1, "track": "learn"},
    ])
    # "ghost" is registered but never placed on disk -- one direction of drift.
    # Separately drop a real file with no manifest entry at all -- the other direction.
    shutil.copy(os.path.join(FIXTURES, "good_exercise.sv"),
                os.path.join(root, "learn", "orphan.sv"))

    r = run([sys.executable, os.path.join(root, "scripts", "check_manifest_sync.py")])
    ok = (r.returncode != 0
          and "ghost" in r.stderr and "doesn't exist on disk" in r.stderr
          and "orphan.sv" in r.stderr and "no manifest.toml entry" in r.stderr)
    assert_that(ok, "check_manifest_sync.py catches drift in both directions",
                r.stdout + r.stderr)
    shutil.rmtree(root)
    return 1


def scenario_find_exercise_after():
    # `make watch` auto-advances to the next exercise in track order on a pass
    # (matches rustlings' own watch mode, confirmed directly against its source)
    # by shelling out to find_exercise.py --after <slug> -- this proves that
    # lookup's three real states: mid-track, last-in-track, and an unknown slug.
    # No fixture .sv files needed -- --after only reads manifest.toml, it never
    # touches disk content.
    root = new_scratch_root([
        {"slug": "first", "path": "learn/first.sv", "order": 1},
        {"slug": "second", "path": "learn/second.sv", "order": 2},
        {"slug": "third", "path": "learn/third.sv", "order": 3},
    ])
    find_exercise = os.path.join(root, "scripts", "find_exercise.py")

    r = run([sys.executable, find_exercise, "--after", "first"])
    assert_that(r.returncode == 0 and r.stdout.strip() == "learn/second.sv",
                "find_exercise.py --after resolves the next exercise mid-track",
                r.stdout + r.stderr)

    r = run([sys.executable, find_exercise, "--after", "third"])
    assert_that(r.returncode == 0 and r.stdout.strip() == "",
                "find_exercise.py --after prints nothing for the last exercise "
                "in a track", r.stdout + r.stderr)

    r = run([sys.executable, find_exercise, "--after", "does_not_exist"])
    assert_that(r.returncode != 0 and "no exercise with slug" in r.stderr,
                "find_exercise.py --after errors on an unknown slug",
                r.stdout + r.stderr)

    shutil.rmtree(root)
    return 3


# ---------------------------------------------------------------------------
# Verilator scenarios: check_unpatched_fails.py and check_patches_pass.py
# actually compile and run the fixtures.
# ---------------------------------------------------------------------------

def scenario_unpatched_fails():
    root = new_scratch_root([
        {"slug": "vacuous_checker", "path": "learn/vacuous_checker.sv",
         "order": 1, "fixture": "vacuous_checker.sv"},
        {"slug": "good_exercise", "path": "learn/good_exercise.sv",
         "order": 2, "fixture": "good_exercise.sv"},
    ])
    r = run([sys.executable, os.path.join(root, "scripts", "check_unpatched_fails.py")])
    ok = (r.returncode != 0
          and "vacuous_checker" in r.stdout and "PROBLEM" in r.stdout
          and "good_exercise" in r.stdout and "fails as expected" in r.stdout)
    assert_that(ok,
                "check_unpatched_fails.py flags the vacuous checker and passes "
                "the good exercise", r.stdout + r.stderr)
    shutil.rmtree(root)
    return 1


def scenario_patches_pass_accepts_good():
    # Isolated in its own scratch root, not combined with the rejection scenario
    # below -- check_patches_pass.py applies every patch in a manifest into one
    # shared copytree per invocation, so two entries can't safely target the same
    # underlying path (both these patches' headers name learn/good_exercise.sv).
    root = new_scratch_root([
        {"slug": "good_exercise", "path": "learn/good_exercise.sv", "order": 1,
         "fixture": "good_exercise.sv", "patch": "good_exercise.patch"},
    ])
    r = run([sys.executable, os.path.join(root, "scripts", "check_patches_pass.py")])
    ok = r.returncode == 0 and "all 1 verifiable patches apply safely" in r.stdout
    assert_that(ok, "check_patches_pass.py accepts a genuinely correct patch",
                r.stdout + r.stderr)
    shutil.rmtree(root)
    return 1


def scenario_patches_pass_rejects_non_solving():
    root = new_scratch_root([
        {"slug": "non_solving_case", "path": "learn/good_exercise.sv", "order": 1,
         "fixture": "good_exercise.sv", "patch": "non_solving.patch"},
    ])
    r = run([sys.executable, os.path.join(root, "scripts", "check_patches_pass.py")])
    ok = (r.returncode != 0 and "non_solving_case" in r.stderr
          and "PATCH DOES NOT SOLVE" in r.stderr)
    assert_that(ok,
                "check_patches_pass.py rejects a patch that doesn't actually solve "
                "the bug", r.stdout + r.stderr)
    shutil.rmtree(root)
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--group", choices=["no-verilator", "verilator", "all"],
                         default="all")
    args = parser.parse_args()

    ran = 0
    if args.group in ("no-verilator", "all"):
        n = (scenario_patch_safety() + scenario_manifest_sync()
             + scenario_find_exercise_after())
        if args.group == "no-verilator":
            assert_that(n == EXPECTED_NO_VERILATOR_CHECKS,
                        f"ran the expected {EXPECTED_NO_VERILATOR_CHECKS} "
                        f"no-verilator checks (ran {n})")
        ran += n

    if args.group in ("verilator", "all"):
        n = (scenario_unpatched_fails()
             + scenario_patches_pass_accepts_good()
             + scenario_patches_pass_rejects_non_solving())
        if args.group == "verilator":
            assert_that(n == EXPECTED_VERILATOR_CHECKS,
                        f"ran the expected {EXPECTED_VERILATOR_CHECKS} "
                        f"verilator checks (ran {n})")
        ran += n

    if args.group == "all":
        expected = EXPECTED_NO_VERILATOR_CHECKS + EXPECTED_VERILATOR_CHECKS
        assert_that(ran == expected,
                    f"ran the expected {expected} total checks (ran {ran})")

    print(f"\nall {ran} checker self-test assertions passed")


if __name__ == "__main__":
    main()
