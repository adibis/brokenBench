# Solved patterns — staging area

Working area for the "solve first, then decide what to strip out to make an exercise" process
(see `~/Claude/plans/brokenbench/plan.md`). Each file here is a fully correct, verified-passing
reference implementation for a named interview pattern, built *before* deciding what to break.

Not final exercises yet — once a pattern is turned into a real `exercises/` entry (bordered
header, question-framed explanation, target block, broken starting state), this staging copy
becomes the seed for `patches/answers/` in the not-yet-built patches infrastructure. Nothing here
is polished prose; these are working drafts, verified by actually running them through Verilator.

## Status

- `01_frame_diff.sv` — DONE, verified passing. Video frames differing by exactly one pixel,
  using `pre_randomize`/`post_randomize` to remember the previous frame.
- `02_unique_ids.sv` — DONE, verified passing. Unique IDs across repeated `randomize()` calls,
  tracked via a queue + `inside {}` (not `randc` — see note below).
- `03_memory_overlap.sv` — DONE, verified passing. `EX_15` was already solid as-is (buggy state
  fails, correct fix passes) — this is that correct fix (`base[i] + size[i] <= base[i+1]` instead
  of just `base[i] < base[i+1]`), reused rather than rewritten from scratch.
- `04_alignment.sv` — DONE, verified passing. 4K-page-aligned address generation (`addr[11:0] ==
  12'b0`), richer than `EX_04`'s single 4-byte-alignment case. Verified a realistic wrong answer
  (off-by-one bit count — `addr[10:0]==11'b0`, which is 2K-alignment not 4K) is correctly caught.
- `05_risc_v_hazard.sv` — DONE, verified passing (now `EX_25`, fields renamed `dst_reg`/
  `src_reg_0`/`src_reg_1` for clarity). A sequence of instructions where each one creates a
  register data hazard against the *previous* instruction's destination register 70% of the time
  (`dist`-weighted), same "remember the last randomize() result" technique as pattern 1, applied
  to an ISA/pipeline-flavored scenario instead of a pixel grid.
- `06_hazard_which_register.sv` — DONE, verified passing (now `EX_26`). Extends pattern 5:
  *given* `gen_hazard` is 1, which register(s) it hits (`src_reg_0`-only, `src_reg_1`-only, or
  both) is itself weighted 20/50/30, conditional on the hazard happening at all. Went through two
  rounds of expert DV review before building (see plan.md) — key corrections from that process:
  the 20/50/30 is conditional on `hazard==1`, not unconditional over all instructions; and a
  proposed "exclude branch/jump from all hazards" idea was corrected to "branches still read
  registers (hazard *consumers*), only unconditional-jump-with-no-register-operand is fully
  excluded" — both reviewers caught this independently.

All 6 solved patterns are now built and verified. Next step per the plan: decide what to strip
out of each to create the broken starting state, then give each the full exercise treatment.

## Real Verilator findings from building these (verify before trusting, don't just copy this text)

1. **`randc` doesn't do what you'd want for ID generation.** A `randc` field's cyclic
   no-immediate-repeat guarantee holds under a *static* constraint (e.g. excluding two literal
   values) but completely breaks under a *dynamic* one (e.g. excluding the previous call's value
   via `post_randomize` state) — confirmed empirically: with `id != last_id`, repeats start
   almost immediately (call 2 of 40) instead of only after all legal values are exhausted. This
   is why `02_unique_ids.sv` uses a plain `rand` field + a used-value queue instead of `randc`.
2. **Indexing a non-rand array by a `rand` variable inside a constraint breaks Verilator's SMT
   solver.** `bit used[16]; constraint c { !used[id]; }` (where `id` is `rand`) produces a
   genuine Verilator solver error (`"select requires 1 arguments, but was provided with 2"`),
   not a logic bug in the SV. The queue + `inside {}` idiom (already used by `EX_01`) avoids this
   entirely and is the pattern to reuse for any "exclude a set of already-used values" constraint.
3. **`int x = 0;` declared inside a `begin...end` block inside a loop, without `automatic`,
   defaults to static lifetime under Verilator** (IEEE 1800-2023 6.21) — the initializer runs
   once, not every loop iteration, so it silently accumulates instead of resetting. Looks exactly
   like a randomization bug until traced with real debug output. Always use `automatic` for
   loop-body-local accumulator variables, or declare once outside the loop and assign (not
   re-declare) inside it.
4. **Comparing two whole unpacked 2D arrays with `!=` inside a constraint fails outright in
   Verilator**, regardless of any `if` guard around it: `constraint c { frame != prev_frame; }`
   produces a genuine solver error (`"Sorts (Array ...) and (_ BitVec 8) are incompatible"`), not
   a satisfiability failure — confirmed it fails even when wrapped in `if (has_prev) frame !=
   prev_frame;` where `has_prev` is false, so it's not even reaching the comparison logically, the
   solver just can't translate whole-array `!=` into SMT at all. This is exactly the "obvious
   first attempt" someone reaches for when asked "make this frame differ from the last one" —
   real, current, and became `01_frame_diff`'s actual bug rather than an invented one.
5. **`dist` on an enum-typed `rand` variable doesn't distribute correctly in Verilator**, even
   though the identical weights on a plain `bit` field of the same width work exactly as
   specified. Confirmed on two variants: `typedef enum bit [1:0] {H_SRC0=0, H_SRC1=1, H_BOTH=2}`
   with explicit values, and a default-encoded `typedef enum {H_SRC0, H_SRC1, H_BOTH}` — both
   trend toward a roughly uniform 1/3-each split regardless of the stated `:=` weights, instead of
   the intended 20/50/30. The identical `dist {0:=20, 1:=50, 2:=30}` on `rand bit [1:0]` lands
   within a percentage point of target over 2000 trials. Workaround: don't use an enum type for a
   weighted-`dist` field in Verilator — use a plain sized `bit` field with documented numeric
   meanings instead (`06_hazard_which_register.sv` does this: `hkind` is `bit [1:0]`, not an
   enum).
6. **A missing "exclude the non-hazarding register" constraint is a real bug, but it's a soft one
   statistically** — leaving `src_reg_1` unconstrained when only `src_reg_0` is meant to hazard
   lets it coincidentally match `prev_dst_reg` by chance (~1/32 for a 5-bit register), silently
   reclassifying a small fraction of "src0-only" instances as "both" in the observed statistics.
   At 20000 trials this is a real, measurable ~2-percentage-point shift in the "both" bucket
   (30.2% correct vs 32.3% leaky), but tight enough that reliably catching it needs either a very
   large sample size or tolerance bands narrow enough to risk false failures on a correct
   implementation across different environments/Verilator versions. `06_hazard_which_register.sv`
   keeps generous tolerance bands rather than chase this specific edge case with a fragile check
   — the exercise's primary, dominant failure mode (a blank/missing implementation) still fails
   hard and unambiguously; this narrower leak is a known, documented limitation of the checker,
   not a silent gap pretending to be rigorous.
