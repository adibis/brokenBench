#!/usr/bin/env python3
"""End-to-end check of web/runner.py against real Verilator builds.

    python3 web/test_runner.py            # learn/ and sv/ exercises
    python3 web/test_runner.py --all      # every track, UVM included (slow)

Starts the runner on a spare port and sends each exercise twice: its stub
must fail and its solution must pass. Also checks the request guards, and
that the runner's Verilator flags still match the Makefile's.
"""

import json
import os
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import export  # noqa: E402
import runner  # noqa: E402


def post(base, body):
    req = urllib.request.Request(base + "/run", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.status, json.load(r)
    except urllib.error.HTTPError as e:
        return e.code, json.load(e)


def main():
    with open(os.path.join(runner.REPO, "Makefile")) as f:
        make_flags = re.search(r"^VFLAGS\s*:=\s*(.+)$", f.read(), re.M).group(1).split()
    assert make_flags == runner.VFLAGS, f"Makefile VFLAGS {make_flags} != runner {runner.VFLAGS}"

    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    srv = subprocess.Popen([sys.executable, os.path.join(HERE, "runner.py"), "--port", str(port),
                            "--per-minute", "1000"])
    base = f"http://127.0.0.1:{port}"
    try:
        for _ in range(50):
            try:
                urllib.request.urlopen(base + "/health"); break
            except OSError:
                time.sleep(0.2)
        exercises = {e["slug"]: e for e in json.loads(
            subprocess.check_output([sys.executable, os.path.join(HERE, "export.py")]))}
        failures = []

        def expect(name, got, want):
            ok = got == want
            print(f"{'ok  ' if ok else 'FAIL'} {name}: {got}")
            if not ok:
                failures.append(name)

        first = next(iter(exercises.values()))
        expect("unknown slug", post(base, {"slug": "nope", "code": ""})[0], 404)
        expect("checker in code", post(base, {"slug": first["slug"],
               "code": first["code"] + runner.MARKER + "\n"})[0], 400)
        expect("syntax error", post(base, {"slug": first["slug"],
               "code": first["code"] + "\nclass ;\n"})[1].get("status"), "compile_error")

        # A page that asks for progress hears each stage, then the result.
        body = json.dumps({"slug": first["slug"], "code": first["solution"]}).encode()
        req = urllib.request.Request(base + "/run", body, {"Content-Type": "application/json",
                                                           "Accept": "application/x-ndjson"})
        with urllib.request.urlopen(req, timeout=600) as r:
            lines = [json.loads(line) for line in r]
        expect("streamed stages", [j.get("stage") or j.get("status") for j in lines],
               ["compiling", "simulating", "pass"])

        # A second run from the same address while the first is still going.
        slow = next(e for e in exercises.values() if e["uvm"])
        t = threading.Thread(target=post, args=(base, {"slug": slow["slug"], "code": slow["code"]}))
        t.start()
        time.sleep(1)
        expect("second run in flight", post(base, {"slug": first["slug"], "code": first["code"]})[0], 429)
        t.join()

        for e in exercises.values():
            if e["track"] not in ("learn", "sv") and "--all" not in sys.argv:
                continue
            if e["needs_patched_verilator"]:
                print(f"skip {e['slug']}: needs a patched Verilator")
                continue
            # Some stubs are meant not to compile; none may pass.
            r = post(base, {"slug": e["slug"], "code": e["code"]})[1]
            expect(f"{e['slug']} stub doesn't pass", r["status"] != "pass", True)
            r = post(base, {"slug": e["slug"], "code": e["solution"]})[1]
            expect(f"{e['slug']} solution ({r.get('seconds')} s)", r["status"], "pass")
        print(f"\n{len(failures)} failed" + (": " + ", ".join(failures) if failures else ""))
        sys.exit(1 if failures else 0)
    finally:
        srv.terminate()


if __name__ == "__main__":
    main()
