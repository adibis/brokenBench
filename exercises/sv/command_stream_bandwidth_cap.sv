// =================================================================================================
// aggregate constraints on an array of structs: what with() can and can't do here
// =================================================================================================
//
// Array reduction/locator methods (`sum()`, `find()`, ... `with (...)`) are the normal SystemVerilog
// tool for aggregate constraints -- "exactly N elements satisfy X," "the total of some field stays
// under a cap." On the current toolchain, none of that machinery works reliably once the array
// holds a STRUCT instead of a plain scalar type -- confirmed directly, not assumed:
//
//   - `array.find() with (...)` inside a constraint block compiles, but is silently dropped --
//     `%Warning-CONSTRAINTIGN: Unsupported: randomizing this expression, treating as state`. It
//     reports randomize() success while enforcing nothing. This is true for locator methods on
//     any array, struct-typed or not.
//   - `struct_array.sum() with (...)` -- for ANY struct-typed array, regardless of what the with
//     expression computes -- generates a malformed query the solver itself rejects
//     (`Sorts (...) are incompatible`), and randomize() reports failure (returns 0) instead of
//     succeeding. Confirmed down to the simplest possible case: a one-field struct, summed with
//     no cast, no filter, no transformation at all. This is specific to the array holding a
//     struct -- the identical reduction on a plain (non-struct) array of the same element type
//     works correctly.
//   - Comparing an enum-typed field against an enum value (`item.cmd_type == WRITE`) inside ANY
//     with (...) clause crashes the compiler outright, independent of the struct issue above --
//     reproduces on a bare enum array too, not just a struct field.
//
// So for this class, every aggregate requirement below needs a different tool. The alternative
// that actually works: express a running total as its own `rand int` array, one element per
// cmd_list entry, related to its neighbor by an ordinary per-element constraint inside `foreach`
// (`running[i] == running[i-1] + (...)`) -- a "prefix sum," built entirely from plain equality
// constraints the solver already handles correctly, with no with (...) clause anywhere. The last
// element of that running array is the total you actually want to bound.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so:
//
//   1. cmd_list.size() is randomized to somewhere between 15 and 20 elements, inclusive. Keep
//      hi_count and dma_running the same length as cmd_list -- they're prefix-sum helper arrays,
//      one running total per position, per the note above.
//   2. Every element's cmd_type is READ, WRITE, or FLUSH -- never INVALID.
//   3. Exactly 3 elements have prio == PRIO_HIGH, via hi_count's prefix-sum recurrence:
//      hi_count[0] is 1 or 0 depending on cmd_list[0].prio, and each later hi_count[i] is
//      hi_count[i-1] plus 1 or 0 depending on cmd_list[i].prio. The last element of hi_count must
//      equal 3.
//   4. Among elements with prio == PRIO_LOW, cmd_type should favor READ and WRITE over FLUSH,
//      roughly 3:3:1.
//   5. dma_running is the same prefix-sum idea, but summing dma_size for WRITE elements only
//      (0 contribution from non-WRITE elements). The last element of dma_running -- the total
//      WRITE bandwidth across the whole stream -- must not exceed 4096. Watch the width: dma_size
//      is only 8 bits, so accumulating into it directly overflows well before 4096; dma_running is
//      declared as a plain int specifically so the running total doesn't wrap.
// -------------------------------------------------------------------------------------------------
typedef enum bit [1:0] {
  READ,
  WRITE,
  FLUSH,
  INVALID
} cmd_e;

typedef enum bit {
  PRIO_LOW,
  PRIO_HIGH
} prio_e;

typedef struct {
  rand cmd_e     cmd_type;
  rand prio_e    prio;
  rand bit [7:0] dma_size;
} cmd_s;

class CommandStream;
  rand cmd_s cmd_list[];
  rand int   hi_count[];      // prefix-sum helper for requirement 3
  rand int   dma_running[];   // prefix-sum helper for requirement 5

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    CommandStream cs;
    bit bad_found = 0;
    int prio_dist_reads_writes = 0;
    int prio_dist_flushes = 0;

    for (int t = 0; t < 30; t++) begin
      automatic int ok;
      automatic int hi_c = 0;
      automatic int w_sum = 0;

      cs = new();
      ok = cs.randomize();

      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d", t);
        $fatal(1);
      end

      if (cs.cmd_list.size() < 15 || cs.cmd_list.size() > 20) begin
        $display("FAIL: cmd_list.size()=%0d is outside [15:20] at call %0d", cs.cmd_list.size(),
                 t);
        bad_found = 1;
      end

      foreach (cs.cmd_list[i]) begin
        if (!(cs.cmd_list[i].cmd_type inside {READ, WRITE, FLUSH})) begin
          $display("FAIL: cmd_list[%0d].cmd_type is INVALID at call %0d", i, t);
          bad_found = 1;
        end
        if (cs.cmd_list[i].prio == PRIO_HIGH) hi_c++;
        if (cs.cmd_list[i].cmd_type == WRITE) w_sum += cs.cmd_list[i].dma_size;
        if (cs.cmd_list[i].prio == PRIO_LOW) begin
          if (cs.cmd_list[i].cmd_type == FLUSH) prio_dist_flushes++;
          else prio_dist_reads_writes++;
        end
      end

      if (hi_c != 3) begin
        $display("FAIL: %0d elements have prio==PRIO_HIGH at call %0d, expected exactly 3", hi_c,
                 t);
        bad_found = 1;
      end

      if (w_sum > 4096) begin
        $display("FAIL: WRITE dma_size total=%0d exceeds 4096 at call %0d", w_sum, t);
        bad_found = 1;
      end

      if (bad_found) $fatal(1);
    end

    // roughly 3:3:1 (reads+writes : flushes) among PRIO_LOW elements, pooled across all 30 calls
    // -- allow a wide band since this is statistical, not exact
    if (prio_dist_flushes == 0
        || prio_dist_reads_writes < prio_dist_flushes * 3
        || prio_dist_reads_writes > prio_dist_flushes * 9) begin
      $display($sformatf({"FAIL: PRIO_LOW reads+writes=%0d vs flushes=%0d, expected roughly a ",
                          "6:1 ratio (3:3:1 collapsed) -- check the dist weights"},
                          prio_dist_reads_writes, prio_dist_flushes));
      $fatal(1);
    end

    $display("PASS: 30 calls, every stream sized/typed/prioritized/bandwidth-capped correctly");
    $finish;
  end
endmodule
