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
- `deploy/`: the container and its Caddy front end.

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

One build at a time (`--slots`), eight waiting (`--queue`), one run in flight
per client address (`--max-in-flight`) and ten a minute (`--per-minute`),
120 s to compile, 60 s to run, 64 KB of code. Builds are compiled at `-O0`:
an unoptimised UVM build takes half the time and half the memory (about
1.8 GB for g++ with `--jobs 1`), and the simulations run no slower, since the
long ones spend their time in the constraint solver.

Every build step runs under CPU-time, memory and file-size limits, and its
output is read back only up to 1 MB. With `--contained` (in the container,
never on your own machine) each run is also held to 128 processes, and
whatever it leaves running is killed when it ends.

## Deploy

`deploy/` holds the container: Verilator built from a pinned release, z3 and
this repo, behind Caddy for HTTPS. The runner's network has no route out, its
file system is read-only apart from a work volume, and it runs unprivileged
with memory and process limits.

```sh
cd web/deploy
SITE_ADDRESS=run.chipdv.io docker compose up -d --build
curl https://run.chipdv.io/health
```

On a 2-core, 4 GB server use `--slots 1 --jobs 2 --output-groups 8`: split
into eight files, a UVM build's two g++ processes need about 1 GB each and
finish in 130 s instead of 185 s; with the default grouping they need 2.6 GB
each and don't fit.

`--cache` keeps finished results so a submission seen before, up to spacing
and comments, returns at once, and `--seed` prebuilds every exercise's
starting code and solution. Only deterministic results are kept, and a
sample of hits is rebuilt while idle to confirm them.

`dma_ring_allocator` needs an unreleased Verilator fix
([verilator#8100](https://github.com/verilator/verilator/pull/8100)); its
page keeps Run disabled until that merges.
