#!/usr/bin/env python3
"""Write every exercise as JSON for the browser editor's pages.

    python3 web/export.py > ../chipdv.io.private/data/brokenbench/exercises.json

For each exercise: its place in the manifest, the spec from the header
comment, the code that follows the header up to the checker marker, any
support files, and the solution (the exercise's patch applied to a scratch
copy, never to this tree) with its diff against that code.
"""

import difflib
import json
import os
import re
import subprocess
import sys
import tempfile
import textwrap

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(REPO, "scripts"))
from find_exercise import parse_manifest  # noqa: E402
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from runner import load_exercises  # noqa: E402

MARKER = "// ---8<--- checker below: don't edit ---"
RULE = re.compile(r"^//\s*[=-]{10,}\s*$")


# The browser never shows the checker, so the specs' pointers to it are
# reworded for the web. The exercise files keep their own wording, which is
# right for someone reading the whole file.
WEB_TEXT = [
    (re.compile(r""", and don't edit anything at or below the "checker" marker\."""), "."),
    (re.compile(r"""\s*[Dd]on't edit anything at or below the "checker" marker[^.]*\."""), ""),
    (re.compile(r"below the (checker )?marker"), "in the test"),
    (re.compile(r"the checker can already see"), "the test can already see"),
    (re.compile(r" so the check after (it|them) passes\."), "."),
]


def for_web(text):
    for pat, rep in WEB_TEXT:
        text = pat.sub(rep, text)
    return text.strip()


def web_comments(code):
    """for_web() over each comment paragraph, re-wrapped only where it changed.

    A paragraph is a run of comment lines between blank comment lines, rules
    and code. Joining before rewording catches sentences that wrap.
    """
    lines = code.splitlines()
    out, run = [], []

    def flush():
        if not run:
            return
        joined = " ".join(l.strip()[2:].strip() for l in run)
        new = for_web(joined)
        if new == joined:
            out.extend(run)
        elif new:
            width = max(len(l) for l in run)
            out.extend(textwrap.wrap(new, width, initial_indent="// ", subsequent_indent="// "))
        elif out and out[-1].strip() == "//":
            out.pop()  # the paragraph is gone; drop the blank comment before it too
        run.clear()

    for line in lines:
        t = line.strip()
        if t.startswith("//") and t != "//" and not RULE.match(t):
            run.append(line)
        else:
            flush()
            out.append(line)
    flush()
    return "\n".join(out) + "\n"


def split(text):
    i = text.index(MARKER)
    return text[:i].rstrip() + "\n", text[i:]


ITEM = re.compile(r"^(\d+\.|[-*])\s")


def header(code):
    """Title and spec from the comment block the file opens with.

    The spec is a list of blocks: {"p": text} for prose, re-joined from its
    wrapped lines, and {"items": [...]} for numbered, bulleted or indented
    lines, which keep their own line each (a wrapped item's continuation
    lines are indented deeper and join it).
    """
    lines = code.splitlines()
    i = 0
    while i < len(lines) and RULE.match(lines[i]):
        i += 1
    title = []
    while i < len(lines) and lines[i].startswith("//") and not RULE.match(lines[i]) \
            and lines[i][2:].strip():
        title.append(lines[i][2:].strip())
        i += 1
    blocks = []
    for line in lines[i:]:
        if not line.strip():
            blocks.append(None)
            continue
        if not line.startswith("//"):
            break
        raw = "" if RULE.match(line) else line[2:].rstrip()
        raw = raw[1:] if raw.startswith(" ") else raw
        text = raw.strip()
        indent = len(raw) - len(raw.lstrip())
        last = blocks[-1] if blocks else None
        if not text:
            blocks.append(None)
        elif last and "items" in last and indent > last["indent"]:
            last["items"][-1] += " " + text
        elif indent >= 2 or ITEM.match(text):
            if last and "items" in last:
                last["items"].append(text)
                last["indent"] = indent
            else:
                blocks.append({"items": [text], "indent": indent})
        elif last and "p" in last:
            last["p"] += " " + text
        else:
            blocks.append({"p": text})
    spec = []
    for b in blocks:
        if not b:
            continue
        spec.append({k: v for k, v in b.items() if k != "indent"})
    title = " ".join(title)
    if title and not re.match(r"^[`\w]+[_(`]", title):
        title = title[0].upper() + title[1:]
    return title, spec


def body(code):
    """The code after the header comment: the page shows the header as the spec."""
    lines = code.splitlines()
    i = 0
    while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith("//")):
        i += 1
    return "\n".join(lines[i:]) + "\n"


def solution(ex):
    patch = os.path.join(REPO, "patches", ex["slug"] + ".patch")
    if not os.path.exists(patch):
        return None
    with tempfile.TemporaryDirectory() as d:
        dst = os.path.join(d, ex["path"])
        os.makedirs(os.path.dirname(dst))
        with open(os.path.join(REPO, ex["path"])) as f, open(dst, "w") as g:
            g.write(f.read())
        r = subprocess.run(["patch", "-p1", "-s", "-i", patch], cwd=d, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"{ex['slug']}: patch doesn't apply: {r.stdout}{r.stderr}")
        with open(dst) as f:
            return split(f.read())[0]


def fix(code, sol):
    """What the solution changes, as diff hunks against the code the editor starts with."""
    d = difflib.unified_diff(code.splitlines(), sol.splitlines(), n=2, lineterm="")
    return "\n".join(list(d)[2:]) + "\n"


def main():
    out = []
    # The runner's own fingerprint of each checker, so a page can tell a
    # runner that grades differently (an older or newer checkout) apart.
    digests = {s: e["digest"] for s, e in load_exercises().items()}
    for ex in sorted(parse_manifest(os.path.join(REPO, "manifest.toml")),
                     key=lambda e: (["learn", "sv", "uvm", "csr"].index(e["track"]), e["order"])):
        with open(os.path.join(REPO, ex["path"])) as f:
            text = f.read()
        full = web_comments(split(text)[0])
        title, spec = header(full)
        code = body(full)
        sol = solution(ex)
        sol = sol and body(web_comments(sol))
        support = []
        for p in ex.get("support", []):
            with open(os.path.join(REPO, p)) as f:
                support.append({"name": os.path.basename(p), "code": f.read()})
        out.append({
            "slug": ex["slug"], "track": ex["track"], "order": ex["order"],
            "digest": digests[ex["slug"]],
            "tags": ex.get("tags", []), "path": ex["path"], "title": title, "spec": spec,
            "uvm": bool(re.search(r"^import uvm_pkg", text, re.M)),
            "needs_patched_verilator": ex.get("requires_patched_verilator", False),
            "code": code, "support": support,
            "solution": sol,
            "fix": sol and fix(code, sol),
        })
    json.dump(out, sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
