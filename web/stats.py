#!/usr/bin/env python3
"""Summarise the runner's request log (runner.py --log).

    python3 web/stats.py runs.jsonl [--days N]
    docker compose exec runner python3 web/stats.py /logs/runs.jsonl

Visitors are counted per UTC day: the log's visitor ids change daily by
design, so a week's total is a sum of daily counts, not distinct people.
"""

import datetime
import json
import statistics
import sys
from collections import Counter, defaultdict


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100 * len(xs)))] if xs else 0


def main():
    args = sys.argv[1:]
    days = int(args[args.index("--days") + 1]) if "--days" in args else None
    since = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=days)
             if days else None)
    runs, refused = [], []
    with open(args[0]) as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if since and datetime.datetime.fromisoformat(r["t"]) < since:
                continue
            (runs if r["event"] == "run" else refused).append(r)

    by_day = defaultdict(lambda: {"runs": 0, "visitors": set(), "refused": 0})
    for r in runs:
        d = by_day[r["t"][:10]]
        d["runs"] += 1
        d["visitors"].add(r["visitor"])
    for r in refused:
        by_day[r["t"][:10]]["refused"] += 1

    print(f"{len(runs)} runs, {len(refused)} turned away")
    print("\nday         visitors  runs  turned away")
    for day in sorted(by_day):
        d = by_day[day]
        print(f"{day}  {len(d['visitors']):8}  {d['runs']:4}  {d['refused']:11}")

    if refused:
        print("\nturned away:", dict(Counter(r["reason"] for r in refused)))
    if not runs:
        return
    print("results:", dict(Counter(r["status"] for r in runs)))

    print("\nseconds        median   p95   max")
    for key in ("wait", "compile", "sim"):
        xs = [r[key] for r in runs]
        print(f"{key:12} {statistics.median(xs):7.1f} {pct(xs, 95):5.1f} {max(xs):5.1f}")

    print("\nexercise                                       runs  passed  visitors")
    per = defaultdict(lambda: [0, 0, set()])
    for r in runs:
        e = per[(r["track"], r["slug"])]
        e[0] += 1
        e[1] += r["status"] == "pass"
        e[2].add(r["t"][:10] + r["visitor"])
    for (track, slug), (n, ok, who) in sorted(per.items(), key=lambda kv: -kv[1][0]):
        print(f"{track + '/' + slug:46} {n:4}  {ok:6}  {len(who):8}")

    print("\nruns by UTC hour:", dict(sorted(Counter(int(r["t"][11:13]) for r in runs).items())))


if __name__ == "__main__":
    main()
