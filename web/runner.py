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
import datetime
import hashlib
import json
import os
import random
import re
import secrets
import shutil
import signal
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
# The C++ is built unoptimised: -O0 halves compile time and the compiler's
# memory on a UVM build, and the simulations run no slower (the long ones
# spend their time in the constraint solver, not the generated code).
BUILD_OPT = ["-MAKEFLAGS", "OPT_FAST=-O0", "-MAKEFLAGS", "OPT_GLOBAL=-O0"]
MAX_CODE = 64 * 1024
MAX_OUTPUT = 32 * 1024
MAX_LOG = 1024 * 1024
CACHE_FAIL_UNDER = 3.0  # s of simulation; well inside the solver's 10 s
CACHE_FORMAT = 1  # bump to drop every cached result
MAX_PROCS = 128  # per run, contained; the container allows twice that


def load_exercises():
    out = {}
    for e in parse_manifest(os.path.join(REPO, "manifest.toml")):
        with open(os.path.join(REPO, e["path"])) as f:
            text = f.read()
        if MARKER not in text:
            raise SystemExit(f"{e['path']}: no checker marker")
        e["checker"] = text[text.index(MARKER):]
        e["uvm"] = bool(re.search(r"^import uvm_pkg", text, re.M))
        h = hashlib.sha256(e["checker"].encode())
        for s in e.get("support", []):
            with open(os.path.join(REPO, s), "rb") as f:
                h.update(f.read())
        e["digest"] = h.hexdigest()  # what besides the visitor's code decides a result
        out[e["slug"]] = e
    return out


def procs_in_session(sid):
    out = []
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                with open(f"/proc/{d}/stat") as f:
                    # Fields after the parenthesised command: state ppid pgrp session ...
                    if int(f.read().rsplit(")", 1)[1].split()[3]) == sid:
                        out.append(int(d))
            except (OSError, IndexError, ValueError):
                pass
    return out


def kill_all(pids):
    for pid in pids:
        try:
            os.kill(pid, 9)
        except (ProcessLookupError, PermissionError):
            pass


def kill_strays():
    """Kill every process in the container but init and this one.

    Only called with no build running, so anything else alive was left by a
    run, including processes that escaped their session with setsid.
    """
    for _ in range(20):
        strays = [int(d) for d in os.listdir("/proc")
                  if d.isdigit() and int(d) not in (1, os.getpid())]
        if not strays:
            return
        kill_all(strays)
        time.sleep(0.05)


def run_capped(cmd, cwd, env, log, timeout, cpu, mem_mb, fsize_mb, contained):
    """Run cmd with its output in the file log; return (returncode, output, timed_out).

    Limits are set by a shell wrapper rather than a preexec_fn, which isn't
    safe in a threaded server; one ulimit per option, since dash takes only
    one. Output goes to a file under the size limit and only its head is
    read back, so a flood of output can't grow this process. The command
    gets its own session, killed afterwards so nothing it left running
    outlives the run. Contained (alone in a container), the run is also held
    to a process count, and the session is swept until empty, since a fork
    bomb outruns a single kill.
    """
    # macOS refuses -v; there it's local mode, on the user's own machine.
    limits = f"ulimit -t {cpu}; ulimit -v {mem_mb * 1024} 2>/dev/null; ulimit -f {fsize_mb * 2048}"
    if contained:
        limits += f"; ulimit -u {MAX_PROCS}"
    with open(log, "wb") as f:
        p = subprocess.Popen(["sh", "-c", limits + '; exec "$@"', "sh", *cmd], cwd=cwd, env=env,
                             stdout=f, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            p.wait(timeout=timeout)
            timed_out = False
        except subprocess.TimeoutExpired:
            timed_out = True
        try:
            os.killpg(p.pid, 9)
        except (ProcessLookupError, PermissionError):  # macOS: EPERM for a group already gone
            pass
        p.wait()
        if contained:
            for _ in range(20):
                left = procs_in_session(p.pid)
                if not left:
                    break
                kill_all(left)
                time.sleep(0.05)
    with open(log, "rb") as f:
        out = f.read(MAX_LOG).decode(errors="replace")
    return (-9 if timed_out else p.returncode), out, timed_out


LIMIT_HIT = {
    signal.SIGXCPU: "\n\nStopped: used more CPU time than a run is allowed.",
    signal.SIGXFSZ: "\n\nStopped: wrote a file larger than a run is allowed.",
}


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


def run_exercise(ex, code, args, times):
    """Build and run; times gets the seconds spent compiling and simulating."""
    work = tempfile.mkdtemp(prefix="bb-")
    try:
        src = os.path.join(work, os.path.basename(ex["path"]))
        with open(src, "w") as f:
            f.write(code.rstrip() + "\n\n" + ex["checker"])
        files = ([UVM_PKG] if ex["uvm"] else []) + \
                [os.path.join(REPO, s) for s in ex.get("support", [])] + [src]
        # Verilator runs make with at least two jobs; a second -j caps it, so
        # --jobs 1 really means one compiler process and its memory.
        jobs = ["-j", args.jobs] + (["-MAKEFLAGS", f"-j{args.jobs}"] if args.jobs != "0" else [])
        if args.output_groups:
            # More, smaller files: with several jobs, each compiler needs less memory.
            jobs += ["--output-groups", str(args.output_groups)]
        cmd = [args.verilator, *VFLAGS, *jobs, *BUILD_OPT, *files,
               "--top-module", "top", "-o", "sim", "-Mdir", os.path.join(work, "obj")]
        env = dict(os.environ)
        if args.objcache:
            env["OBJCACHE"] = args.objcache
        t0 = time.monotonic()
        rc, log, timed_out = run_capped(cmd, REPO, env, os.path.join(work, "compile.log"),
                                        args.compile_timeout, args.compile_timeout * 2,
                                        args.compile_mem, 512, args.contained)
        times["compile"] = time.monotonic() - t0
        if timed_out:
            return {"status": "timeout", "stage": "compile",
                    "output": f"Compile took longer than {args.compile_timeout} s and was stopped."}
        if rc != 0:
            # Verilator's own errors (file:line) are deterministic; a failed
            # C++ build may be a compiler killed for memory, so never cached.
            own = re.search(r"^%Error(-\w+)?: [^\s:]+:\d+", log, re.M) and "'make " not in log
            return {"status": "compile_error", "cacheable": bool(own and rc > 0),
                    "output": clean_compile_log(log, work) + LIMIT_HIT.get(-rc, "")}
        env = dict(os.environ, VERILATOR_SOLVER=SOLVER)
        t0 = time.monotonic()
        rc, log, timed_out = run_capped([os.path.join(work, "obj", "sim")], work, env,
                                        os.path.join(work, "run.log"), args.run_timeout,
                                        args.run_timeout, args.run_mem, 64, args.contained)
        times["run"] = time.monotonic() - t0
        out = clean_run_log(log)
        if timed_out:
            return {"status": "timeout", "stage": "run",
                    "output": out + f"\n\nSimulation ran longer than {args.run_timeout} s and was stopped."}
        # A pass can't come from load. A fail can, if the constraint solver
        # ran out of time on a busy machine, so only a quick fail is kept.
        quick = times["run"] < CACHE_FAIL_UNDER
        return {"status": "pass" if rc == 0 else "fail", "cacheable": rc == 0 or (rc > 0 and quick),
                "output": out + LIMIT_HIT.get(-rc, "")}
    finally:
        shutil.rmtree(work, ignore_errors=True)


REFUSED = {
    "rate": "Too many runs from your address; wait a minute and try again.",
    "in_flight": "Your previous run is still going; wait for it to finish.",
    "busy": "The runner is busy; try again in a moment.",
}


# Comments that steer Verilator or other tools; they stay part of the code.
TOOL_COMMENT = re.compile(r"verilator|synopsys|synthesis|pragma|lint|translate", re.I)


def normalize(code):
    """The code with comments and spacing evened out, every line kept in place.

    Two submissions that differ only in indentation, spacing or ordinary
    comments normalise the same, and line numbers in a result still point
    at the right lines. Strings, including multi-line ones, and tool
    comments are copied untouched.
    """
    out, i, n = [], 0, len(code)

    def newline():
        while out and out[-1] == " ":
            out.pop()
        out.append("\n")

    while i < n:
        c = code[i]
        if code.startswith('"""', i):
            j = code.find('"""', i + 3)
            j = n if j < 0 else j + 3
            out.append(code[i:j])
            i = j
        elif c == '"':
            j = i + 1
            while j < n and code[j] not in '"\n':
                j += 2 if code[j] == "\\" else 1
            out.append(code[i:j + 1])
            i = j + 1
        elif code.startswith("//", i):
            j = code.find("\n", i)
            j = n if j < 0 else j
            if TOOL_COMMENT.search(code[i:j]):
                out.append(code[i:j])
            i = j
        elif code.startswith("/*", i):
            j = code.find("*/", i + 2)
            j = n if j < 0 else j + 2
            body = code[i:j]
            if TOOL_COMMENT.search(body):
                out.append(body)
            else:
                for _ in range(body.count("\n")):
                    newline()
            i = j
        elif c == "\n":
            newline()
            i += 1
        elif c in " \t\r":
            while i < n and code[i] in " \t\r":
                i += 1
            if out and out[-1] != "\n":  # nothing at the start of a line
                out.append(" ")
        else:
            out.append(c)
            i += 1
    return "".join(out).rstrip()


class ResultCache:
    """Finished results, so a submission seen before comes back at once.

    Keyed by the exercise, its checker, the Verilator version, the build
    flags and the code: normalised for a pass or fail, exact for a compile
    error, whose messages carry columns. Only deterministic outcomes are
    kept (simulations run with a fixed seed): never a timeout or a run that
    hit a resource limit. No code is stored, only its hash. Seeded results
    (every exercise's starting code and solution) are kept for good; the
    rest are dropped least recently used first above max_mb.
    """

    def __init__(self, path, version, max_mb=2048):
        self.path = path
        # Everything outside the exercise that can change a result.
        h = hashlib.sha256(json.dumps([CACHE_FORMAT, version, VFLAGS, BUILD_OPT, SOLVER]).encode())
        z3 = subprocess.run(["z3", "--version"], capture_output=True, text=True)
        h.update(z3.stdout.encode())
        for d, _, files in sorted(os.walk(os.path.dirname(UVM_PKG))):
            for name in sorted(files):
                with open(os.path.join(d, name), "rb") as f:
                    h.update(name.encode() + f.read())
        self.env = h.hexdigest()
        self.max_bytes = max_mb * 1024 * 1024
        self.writes = 0
        self.lock = threading.Lock()
        if path:
            for sub in ("seed", "lru"):
                os.makedirs(os.path.join(path, sub), exist_ok=True)

    def key(self, ex, code, exact):
        text = code.rstrip() if exact else normalize(code)
        blob = json.dumps([ex["slug"], ex["digest"], self.env, text])
        return hashlib.sha256(blob.encode()).hexdigest()

    def get(self, ex, code):
        if not self.path:
            return None
        for exact in (False, True):
            name = self.key(ex, code, exact) + ".json"
            for sub in ("seed", "lru"):
                f = os.path.join(self.path, sub, name)
                try:
                    with open(f) as fh:
                        hit = json.load(fh)
                except (OSError, ValueError):
                    continue
                if sub == "lru":
                    try:
                        os.utime(f)
                    except OSError:
                        pass
                return hit
        return None

    def put(self, ex, code, result, pinned=False):
        status = result["status"]
        if not self.path or not result.get("cacheable"):
            return
        sub = os.path.join(self.path, "seed" if pinned else "lru")
        tmp = os.path.join(sub, f".{secrets.token_hex(8)}.tmp")
        with open(tmp, "w") as f:
            json.dump({"status": status, "output": result["output"]}, f)
        os.replace(tmp, os.path.join(sub, self.key(ex, code, status == "compile_error") + ".json"))
        with self.lock:
            self.writes += 1
            if self.writes % 100 == 0:
                self.prune()

    def drop(self, ex, code):
        for exact in (False, True):
            for sub in ("seed", "lru"):
                try:
                    os.remove(os.path.join(self.path, sub, self.key(ex, code, exact) + ".json"))
                except OSError:
                    pass

    def prune(self):
        sub = os.path.join(self.path, "lru")
        files = []
        for name in os.listdir(sub):
            try:
                st = os.stat(os.path.join(sub, name))
                files.append((st.st_mtime, st.st_size, name))
            except OSError:
                pass
        total = sum(s for _, s, _ in files)
        for _, size, name in sorted(files):
            if total <= self.max_bytes * 0.8:
                break
            try:
                os.remove(os.path.join(sub, name))
                total -= size
            except OSError:
                pass


def seed(exercises, gate, cache, args):
    """Build every exercise's starting code and solution into the cache.

    Runs through the same gate as visitors, one build at a time, so it never
    competes with a visitor's build for memory; already cached entries are
    skipped, so a restart resumes where it stopped.
    """
    pages = json.loads(subprocess.check_output([sys.executable, os.path.join(REPO, "web", "export.py")]))
    solutions = {p["slug"]: p["solution"] for p in pages}
    todo = [(exercises[p["slug"]], c) for p in pages if not p["needs_patched_verilator"]
            for c in (p["code"], p["solution"]) if c]
    todo = [(ex, c) for ex, c in todo if cache.get(ex, c) is None]
    sys.stderr.write(f"seeding {len(todo)} results\n")
    for i, (ex, code) in enumerate(todo, 1):
        with gate.lock:
            gate.waiting += 1
        with gate:
            result = run_exercise(ex, code, args, {})
        if code == solutions[ex["slug"]] and result["status"] != "pass":
            sys.stderr.write(f"NOT SEEDED: {ex['slug']} solution gave {result['status']}\n")
            continue
        cache.put(ex, code, result, pinned=True)
        sys.stderr.write(f"seeded {i}/{len(todo)} {ex['slug']}: {result['status']}\n")


def verify_cached(queue, gate, cache, runlog, args):
    """Rebuild a sample of cache hits while the runner is idle.

    If a fresh build disagrees with what was served, the entry is dropped
    and the mismatch logged, so a wrong cached result can't live on.
    """
    while True:
        time.sleep(5)
        with gate.lock:
            idle = gate.running == 0 and gate.waiting == 0
        if not idle or not queue:
            continue
        ex, code, served = queue.popleft()
        with gate.lock:
            gate.waiting += 1
        with gate:
            fresh = run_exercise(ex, code, args, {})
        agree = fresh["status"] == served["status"]
        if not agree and fresh["status"] != "timeout":
            cache.drop(ex, code)
        runlog.write("verify", event="verify", slug=ex["slug"], served=served["status"],
                     fresh=fresh["status"], agree=agree)


class RunLog:
    """One JSON line per request, for usage numbers, without addresses.

    A visitor is a hash of their address with a random salt that changes
    each UTC day and is never stored: distinct visitors can be counted
    within a day, but no address can be recovered or followed across days.
    """

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.day = None
        self.salt = b""

    def visitor(self, ip):
        day = datetime.datetime.now(datetime.timezone.utc).date()
        if day != self.day:
            self.day, self.salt = day, secrets.token_bytes(16)
        return hashlib.sha256(self.salt + ip.encode()).hexdigest()[:12]

    def write(self, ip, **fields):
        if not self.path:
            return
        with self.lock:
            rec = {"t": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
                   "visitor": self.visitor(ip), **fields}
            try:
                with open(self.path, "a") as f:
                    f.write(json.dumps(rec) + "\n")
            except OSError as e:
                sys.stderr.write(f"run log: {e}\n")


class Gate:
    """At most `slots` builds at once, `queue` waiting, one per address, and a per-address rate."""

    def __init__(self, slots, queue, per_minute, max_in_flight=1):
        self.sem = threading.BoundedSemaphore(slots)
        self.lock = threading.Lock()
        self.waiting = 0
        self.running = 0
        self.contained = False
        self.queue = queue
        self.per_minute = per_minute
        self.hits = defaultdict(deque)
        self.in_flight = defaultdict(int)
        self.max_in_flight = max_in_flight

    def admit(self, ip):
        now = time.monotonic()
        with self.lock:
            h = self.hits[ip]
            while h and now - h[0] > 60:
                h.popleft()
            if len(h) >= self.per_minute:
                return "rate"
            # One run at a time per address, so one client can't fill the queue.
            if self.in_flight[ip] >= self.max_in_flight:
                return "in_flight"
            if self.waiting >= self.queue:
                return "busy"
            h.append(now)
            self.waiting += 1
            self.in_flight[ip] += 1
        return None

    def done(self, ip):
        with self.lock:
            self.in_flight[ip] -= 1
            if not self.in_flight[ip]:
                del self.in_flight[ip]

    def __enter__(self):
        self.sem.acquire()
        with self.lock:
            self.waiting -= 1
            self.running += 1

    def __exit__(self, *exc):
        with self.lock:
            self.running -= 1
            if self.contained and self.running == 0:
                kill_strays()
        self.sem.release()


class Server(ThreadingHTTPServer):
    # The default backlog of 5 refuses a burst outright; queued, each gets a clean 429.
    request_queue_size = 128


def make_handler(exercises, gate, runlog, cache, checks, args):
    class Handler(BaseHTTPRequestHandler):
        server_version = "brokenbench-runner"
        timeout = 20  # a client that stalls mid-request is dropped, not waited on

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
            hit = cache.get(ex, code)
            if hit:
                # Costs nothing to serve, so it skips the queue and the limits.
                runlog.write(ip, event="run", slug=slug, track=ex["track"], status=hit["status"],
                             cached=True)
                if random.random() < args.verify_rate:
                    checks.append((ex, code, hit))
                return self.reply(200, {**hit, "seconds": 0.1, "uvm": ex["uvm"], "cached": True})
            refused = gate.admit(ip)
            if refused:
                runlog.write(ip, event="refused", reason=refused, slug=slug)
                return self.reply(429, {"error": REFUSED[refused]})
            t0 = time.monotonic()
            times = {}
            try:
                with gate:
                    waited = time.monotonic() - t0
                    result = run_exercise(ex, code, args, times)
            finally:
                gate.done(ip)
            cache.put(ex, code, result)
            result.pop("cacheable", None)
            runlog.write(ip, event="run", slug=slug, track=ex["track"], status=result["status"],
                         wait=round(waited, 1), compile=round(times.get("compile", 0), 1),
                         sim=round(times.get("run", 0), 1))
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
    ap.add_argument("--jobs", default="0", help="compiler jobs per build (0: one per core)")
    ap.add_argument("--output-groups", type=int, default=0,
                    help="split the generated C++ into this many files (0: Verilator's default)")
    ap.add_argument("--queue", type=int, default=8, help="builds allowed to wait")
    ap.add_argument("--per-minute", type=int, default=10, help="runs per client address per minute")
    ap.add_argument("--max-in-flight", type=int, default=1,
                    help="runs one client address may have queued or running at once")
    ap.add_argument("--compile-timeout", type=int, default=120)
    ap.add_argument("--run-timeout", type=int, default=60)  # constraint-heavy SV runs take ~25 s
    ap.add_argument("--compile-mem", type=int, default=3072, help="MB of address space per compile step")
    ap.add_argument("--run-mem", type=int, default=2048, help="MB of address space for a simulation")
    ap.add_argument("--contained", action="store_true",
                    help="alone in a container: cap each run's processes and kill whatever a run "
                         "leaves behind (never use this outside a container)")
    ap.add_argument("--cache", help="directory of finished results for exact starting code and solutions")
    ap.add_argument("--cache-mb", type=int, default=2048,
                    help="size above which visitors' cached results are dropped, oldest first")
    ap.add_argument("--verify-rate", type=float, default=0.05,
                    help="share of cache hits rebuilt while idle to confirm the cached result")
    ap.add_argument("--seed", action="store_true",
                    help="build every exercise's starting code and solution into --cache, in the background")
    ap.add_argument("--log", help="append a JSON line per request here (no addresses; see RunLog)")
    ap.add_argument("--verilator", default="verilator")
    ap.add_argument("--trust-proxy", action="store_true",
                    help="take the client address from X-Forwarded-For (only behind a proxy that sets it)")
    # Off by default: a cached precompiled header names the work directory it
    # was built in, which is gone by the next run, and clang rejects it.
    ap.add_argument("--objcache", help="compiler cache for Verilator's C++ build, e.g. ccache")
    args = ap.parse_args()
    if args.seed and not args.cache:
        ap.error("--seed needs --cache")
    args.origin = args.origin or [f"http://{h}:{p}" for h in ("localhost", "127.0.0.1")
                                  for p in (1313, 1316)]
    args.version = subprocess.run([args.verilator, "--version"], capture_output=True,
                                  text=True).stdout.strip()
    exercises = load_exercises()
    gate = Gate(args.slots, args.queue, args.per_minute, args.max_in_flight)
    gate.contained = args.contained
    cache = ResultCache(args.cache, args.version, args.cache_mb)
    runlog = RunLog(args.log)
    checks = deque(maxlen=50)
    srv = Server((args.host, args.port), make_handler(exercises, gate, runlog, cache, checks, args))
    if args.cache:
        threading.Thread(target=verify_cached, args=(checks, gate, cache, runlog, args),
                         daemon=True).start()
    if args.seed:
        threading.Thread(target=seed, args=(exercises, gate, cache, args), daemon=True).start()
    print(f"brokenbench runner ({args.version}): {len(exercises)} exercises on http://{args.host}:{args.port}, "
          f"origins {', '.join(args.origin)}", file=sys.stderr)
    srv.serve_forever()


if __name__ == "__main__":
    main()
