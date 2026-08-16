#!/usr/bin/env python3
"""Look up exercises in manifest.toml by slug or by track/tag filter.

Deliberately doesn't depend on tomllib (Python 3.11+) or a third-party toml
package -- this repo's only stated requirement is Verilator, and this parser
only needs to handle manifest.toml's own narrow shape: a flat sequence of
[[exercise]] tables, each with string/int/bool/list-of-string values, no
nesting.
"""

import argparse
import json
import os
import re
import sys

MANIFEST_PATH = os.path.join(os.path.dirname(__file__), "..", "manifest.toml")


def parse_manifest(path):
    exercises = []
    current = None
    with open(path) as f:
        for raw_line in f:
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            if line == "[[exercise]]":
                if current is not None:
                    exercises.append(current)
                current = {}
                continue
            m = re.match(r'^(\w+)\s*=\s*(.+)$', line)
            if not m or current is None:
                continue
            key, raw_value = m.group(1), m.group(2)
            if raw_value.startswith("["):
                items = re.findall(r'"([^"]*)"', raw_value)
                current[key] = items
            elif raw_value.startswith('"'):
                current[key] = raw_value.strip('"')
            elif raw_value in ("true", "false"):
                current[key] = raw_value == "true"
            else:
                current[key] = int(raw_value)
    if current is not None:
        exercises.append(current)
    return exercises


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slug", help="resolve a single exercise's path by its slug")
    parser.add_argument("--track", choices=["learn", "exercises"], help="filter to one track")
    parser.add_argument("--tag", action="append", default=[],
                         help="filter to exercises with this tag (repeatable, AND semantics)")
    parser.add_argument("--list", action="store_true",
                         help="print slug, track, and tags for every match")
    parser.add_argument("--json", action="store_true",
                         help="print full matching entries as a JSON array (for scripts/CI)")
    args = parser.parse_args()

    exercises = parse_manifest(MANIFEST_PATH)

    if args.slug:
        matches = [e for e in exercises if e["slug"] == args.slug]
        if not matches:
            print(f"no exercise with slug '{args.slug}' in manifest.toml", file=sys.stderr)
            sys.exit(1)
        if args.json:
            print(json.dumps(matches[0]))
        else:
            print(matches[0]["path"])
        return

    results = exercises
    if args.track:
        results = [e for e in results if e["track"] == args.track]
    for tag in args.tag:
        results = [e for e in results if tag in e.get("tags", [])]
    results.sort(key=lambda e: (e["track"], e["order"]))

    if not results:
        print("no exercises match that filter", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(results))
        return

    for e in results:
        if args.list:
            print(f"{e['slug']:<45} [{e['track']}] {', '.join(e.get('tags', []))}")
        else:
            print(e["path"])


if __name__ == "__main__":
    main()
