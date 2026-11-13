// =================================================================================================
// aggregate constraints on an array of structs: what with() can and can't do here
// =================================================================================================
//
// Reduction and locator methods with `with (...)` are the usual tool for aggregate constraints
// ("exactly N elements are X", "the total stays under a cap"). On the current toolchain they
// don't work here, confirmed directly:
//
//   - `find() with` in a constraint compiles but is dropped (CONSTRAINTIGN): randomize()
//     succeeds and enforces nothing. True for any array.
//   - `sum() with` on any struct-typed array, even a one-field struct with no cast, produces a
//     query the solver rejects ("Sorts ... are incompatible"), and randomize() returns 0. The same
//     reduction on a plain array works.
//   - Comparing an enum field to an enum value (`item.cmd_type == WRITE`) inside any with (...)
//     crashes the compiler, struct or not.
//
// What works is a prefix sum: a separate `rand int` array, one element per cmd_list entry, each
// tied to the one before it in a foreach (`running[i] == running[i-1] + (...)`). Its last
// element is the total to bound.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. cmd_list.size() is between 15 and 20, inclusive; hi_count and dma_running, the prefix-sum
//      arrays, are the same length.
//   2. Every cmd_type is READ, WRITE or FLUSH, never INVALID.
//   3. Exactly 3 elements have prio == PRIO_HIGH, counted in hi_count: hi_count[0] is 1 or 0 from
//      cmd_list[0].prio, each later hi_count[i] adds 1 or 0 to hi_count[i-1], and the last is 3.
//   4. Among PRIO_LOW elements, cmd_type favors READ and WRITE over FLUSH, about 3:3:1.
//   5. dma_running sums dma_size over WRITE elements only, the same way, and its last element
//      (total WRITE bandwidth) is at most 4096. dma_size is 8 bits and would wrap; dma_running is
//      an int so the total doesn't.
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
  rand cmd_s cmd_list   [];
  rand int   hi_count   [];  // prefix-sum helper for requirement 3
  rand int   dma_running[];  // prefix-sum helper for requirement 5

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
        $display("FAIL: cmd_list.size()=%0d is outside [15:20] at call %0d", cs.cmd_list.size(), t);
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
