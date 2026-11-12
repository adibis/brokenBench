# brokenbench in the browser

The exercise pages on chipdv.io let you edit an exercise and run it without
installing anything. They send your code to `runner.py`, which compiles it
with Verilator together with the exercise's own checker and returns the
result. Only the part above the checker marker comes from the browser, so a
PASS always means the real checker passed.

- `runner.py`: the run service. Python standard library only.
- `export.py`: writes every exercise (code, checker, spec, solution diff) as
  JSON for the site's pages.
- `test_runner.py`: starts the runner and checks that every stub fails, every
  solution passes, and the request guards hold. `--all` includes the UVM and
  CSR tracks, which take about 25 s each to compile.

## Local mode

Run everything on your own machine: the runner here, the site from
chipdv.io's repo. Pages served from `localhost` or `127.0.0.1` call the
runner at `http://127.0.0.1:8787` instead of the deployed one.

```sh
python3 web/runner.py                          # this repo
python3 web/export.py > ../chipdv.io.private/data/brokenbench/exercises.json
hugo server --buildDrafts                      # chipdv.io repo
```

Re-run `export.py` after changing an exercise or its patch. Add `?api=URL`
to an exercise page's address to point it at another runner.

## Limits

One build at a time (`--slots`), eight waiting (`--queue`), ten runs per
client address per minute (`--per-minute`), 300 s to compile, 30 s to run,
64 KB of code. Locally the build runs directly on your machine. Deployed,
the runner will sit in a container with no network, a read-only file
system and memory and CPU limits, because a Verilator build of submitted
code is submitted code running on the server.

`dma_ring_allocator` needs an unreleased Verilator fix
([verilator#8100](https://github.com/verilator/verilator/pull/8100)); its
page keeps Run disabled until that merges.
