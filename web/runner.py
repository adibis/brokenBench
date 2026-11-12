#!/usr/bin/env python3
"""Run brokenbench exercises for the browser editor.

POST /run {"slug": ..., "code": ...} compiles the visitor's code with the
exercise's own checker and returns PASS/FAIL and the output. Only the part
above the checker marker comes from the visitor: the checker is always the
one in this repo, so a PASS means the real checker passed.

    python3 web/runner.py                       # local mode, 127.0.0.1:8787
    python3 web/runner.py --origin https://chipdv.io --host 0.0.0.0

Local mode runs the build directly on this machine. Deployed, the same
service runs inside a locked-down container (see web/README.md).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(REPO, "scripts"))
from find_exercise import parse_manifest  # noqa: E402

MARKER = "// ---8<--- checker below: don't edit ---"
UVM_PKG = os.path.join(REPO, "vendor/uvm/uvm_pkg.svh")
# Same flags and solver bound as the Makefile's run target; test_runner.py
# fails if they drift apart.
VFLAGS = ["--binary", "--timing", "-j", "0", "-Wno-fatal", "-Wno-IMPLICITSTATIC"]
SOLVER = "z3 -t:10000 --in"
MAX_CODE = 64 * 1024
MAX_OUTPUT = 32 * 1024


def load_exercises():
    out = {}
    for e in parse_manifest(os.path.join(REPO, "manifest.toml")):
        with open(os.path.join(REPO, e["path"])) as f:
            text = f.read()
        if MARKER not in text:
            raise SystemExit(f"{e['path']}: no checker marker")
        e["checker"] = text[text.index(MARKER):]
        e["uvm"] = bool(re.search(r"^import uvm_pkg", text, re.M))
        out[e["slug"]] = e
    return out


def run_capped(cmd, cwd, env, timeout, cpu, fsize_mb=256):
    """Run cmd; return (returncode, output, timed_out).

    CPU and file-size limits are set by a shell wrapper rather than a
    preexec_fn, which isn't safe in a threaded server. The command gets its
    own process group so a timeout kills everything it started.
    """
    wrapped = ["sh", "-c", f'ulimit -t {cpu} -f {fsize_mb * 2048}; exec "$@"', "sh", *cmd]
    p = subprocess.Popen(wrapped, cwd=cwd, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=timeout)
        return p.returncode, out.decode(errors="replace"), False
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, 9)
        out, _ = p.communicate()
        return -9, out.decode(errors="replace"), True


def clean_compile_log(log, work):
    log = log.replace(work + "/", "").replace(REPO + "/", "")
    lines = log.splitlines()
    picked = []
    for i, line in enumerate(lines):
        if line.startswith("%Error"):
            picked.extend(lines[i:i + 5])
    return "\n".join(picked or lines[-20:])


def clean_run_log(log):
    # The Makefile drops the same noise: Verilator's own fatal banner and the
    # stack hint that follow a checker's $fatal.
    keep = [l for l in log.splitlines()
            if not re.match(r"^\[.*\] %Fatal|^%Error|^Aborting\.\.\.|^- ", l)]
    return "\n".join(keep).strip()


def run_exercise(ex, code, args):
    work = tempfile.mkdtemp(prefix="bb-")
    try:
        src = os.path.join(work, os.path.basename(ex["path"]))
        with open(src, "w") as f:
            f.write(code.rstrip() + "\n\n" + ex["checker"])
        files = ([UVM_PKG] if ex["uvm"] else []) + \
                [os.path.join(REPO, s) for s in ex.get("support", [])] + [src]
        cmd = [args.verilator, *VFLAGS, *files, "--top-module", "top", "-o", "sim",
               "-Mdir", os.path.join(work, "obj")]
        env = dict(os.environ)
        if args.objcache:
            env["OBJCACHE"] = args.objcache
        rc, log, timed_out = run_capped(cmd, REPO, env, args.compile_timeout,
                                        args.compile_timeout * 8)
        if timed_out:
            return {"status": "timeout", "stage": "compile",
                    "output": f"Compile took longer than {args.compile_timeout} s and was stopped."}
        if rc != 0:
            return {"status": "compile_error", "output": clean_compile_log(log, work)}
        env = dict(os.environ, VERILATOR_SOLVER=SOLVER)
        rc, log, timed_out = run_capped([os.path.join(work, "obj", "sim")], work, env,
                                        args.run_timeout, args.run_timeout)
        out = clean_run_log(log)
        if timed_out:
            return {"status": "timeout", "stage": "run",
                    "output": out + f"\n\nSimulation ran longer than {args.run_timeout} s and was stopped."}
        return {"status": "pass" if rc == 0 else "fail", "output": out}
    finally:
        shutil.rmtree(work, ignore_errors=True)


class Gate:
    """At most `slots` builds at once, at most `queue` waiting, and a per-IP rate."""

    def __init__(self, slots, queue, per_minute):
        self.sem = threading.BoundedSemaphore(slots)
        self.lock = threading.Lock()
        self.waiting = 0
        self.queue = queue
        self.per_minute = per_minute
        self.hits = defaultdict(deque)

    def admit(self, ip):
        now = time.monotonic()
        with self.lock:
            h = self.hits[ip]
            while h and now - h[0] > 60:
                h.popleft()
            if len(h) >= self.per_minute:
                return "Too many runs from your address; wait a minute and try again."
            if self.waiting >= self.queue:
                return "The runner is busy; try again in a moment."
            h.append(now)
            self.waiting += 1
        return None

    def __enter__(self):
        self.sem.acquire()
        with self.lock:
            self.waiting -= 1

    def __exit__(self, *exc):
        self.sem.release()


def make_handler(exercises, gate, args):
    class Handler(BaseHTTPRequestHandler):
        server_version = "brokenbench-runner"

        def cors(self):
            origin = self.headers.get("Origin", "")
            if origin in args.origin:
                self.send_header("Access-Control-Allow-Origin", origin)
                self.send_header("Vary", "Origin")
                self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
                self.send_header("Access-Control-Allow-Headers", "Content-Type")

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.send_response(code)
            self.cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_OPTIONS(self):
            self.send_response(204)
            self.cors()
            self.end_headers()

        def do_GET(self):
            if self.path == "/health":
                return self.reply(200, {"ok": True, "exercises": len(exercises),
                                        "verilator": args.version, "waiting": gate.waiting})
            self.reply(404, {"error": "not found"})

        def do_POST(self):
            if self.path != "/run":
                return self.reply(404, {"error": "not found"})
            try:
                n = int(self.headers.get("Content-Length", 0))
                if n > MAX_CODE + 1024:
                    return self.reply(413, {"error": "Code is too large."})
                req = json.loads(self.rfile.read(n))
                slug, code = req["slug"], req["code"]
            except (ValueError, KeyError, TypeError):
                return self.reply(400, {"error": "Expected JSON with slug and code."})
            ex = exercises.get(slug)
            if ex is None:
                return self.reply(404, {"error": f"No exercise {slug!r}."})
            if not isinstance(code, str) or len(code) > MAX_CODE:
                return self.reply(413, {"error": "Code is too large."})
            if "---8<---" in code:
                return self.reply(400, {"error": "Send only the code above the checker marker."})
            ip = self.client_address[0]
            if args.trust_proxy:
                # The proxy appends the address it saw; anything before it is
                # whatever the client claimed.
                ip = self.headers.get("X-Forwarded-For", ip).split(",")[-1].strip()
            refused = gate.admit(ip)
            if refused:
                return self.reply(429, {"error": refused})
            t0 = time.monotonic()
            with gate:
                result = run_exercise(ex, code, args)
            if len(result["output"]) > MAX_OUTPUT:
                result["output"] = result["output"][:MAX_OUTPUT] + "\n\n[output cut at 32 KB]"
            result["seconds"] = round(time.monotonic() - t0, 1)
            result["uvm"] = ex["uvm"]
            self.reply(200, result)

        def log_message(self, fmt, *a):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % a))

    return Handler


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--origin", action="append",
                    help="allowed browser origin (repeatable); default: local Hugo servers")
    ap.add_argument("--slots", type=int, default=1, help="builds at once")
    ap.add_argument("--queue", type=int, default=8, help="builds allowed to wait")
    ap.add_argument("--per-minute", type=int, default=10, help="runs per client address per minute")
    ap.add_argument("--compile-timeout", type=int, default=300)
    ap.add_argument("--run-timeout", type=int, default=30)
    ap.add_argument("--verilator", default="verilator")
    ap.add_argument("--trust-proxy", action="store_true",
                    help="take the client address from X-Forwarded-For (only behind a proxy that sets it)")
    ap.add_argument("--objcache", default=shutil.which("ccache") and "ccache",
                    help="compiler cache for Verilator's C++ build (default: ccache if installed)")
    args = ap.parse_args()
    args.origin = args.origin or [f"http://{h}:{p}" for h in ("localhost", "127.0.0.1")
                                  for p in (1313, 1316)]
    args.version = subprocess.run([args.verilator, "--version"], capture_output=True,
                                  text=True).stdout.strip()
    exercises = load_exercises()
    gate = Gate(args.slots, args.queue, args.per_minute)
    srv = ThreadingHTTPServer((args.host, args.port), make_handler(exercises, gate, args))
    print(f"brokenbench runner ({args.version}): {len(exercises)} exercises on http://{args.host}:{args.port}, "
          f"origins {', '.join(args.origin)}", file=sys.stderr)
    srv.serve_forever()


if __name__ == "__main__":
    main()
