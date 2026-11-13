// =================================================================================================
// sorted isn't the same as non-overlapping -- unless you check the right pair
// =================================================================================================
//
// Hand out N address ranges that don't overlap. Ordering the starts
// (`regions[0].base < regions[1].base < ...`) looks like enough, but says nothing about where
// each range ends: a large region reaches straight into the next one.
//
// Once the array is sorted by base_addr, each region only needs checking against its immediate
// predecessor. That's the point of keeping it sorted: an all-pairs check becomes an
// adjacent-pairs check.
//
// `regions[i-1]` only makes sense for `i > 0`, and a foreach index is unsigned: guard it with a
// real if/else, or index -1 wraps to the largest value instead of going negative.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. regions.size() is between 4 and 8, inclusive.
//   2. regions[] is in strictly ascending order by base_addr.
//   3. Every region's base_addr is strictly less than its limit_addr.
//   4. Every base_addr and limit_addr is within [32'h0000_0000 : 32'h7FFF_FFFF].
//   5. Every region's size (limit_addr - base_addr + 1; limit_addr is the last byte, inclusive)
//      is a multiple of 4KB (32'h1000).
//   6. Every base_addr is 4KB-aligned.
//   7. No two regions overlap: with requirement 2 in place, check each base_addr against the
//      previous region's limit_addr.
// -------------------------------------------------------------------------------------------------
typedef struct {
  rand bit [31:0] base_addr;
  rand bit [31:0] limit_addr;
} region_s;

class MemoryMap;
  rand region_s regions[];

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    MemoryMap m;
    bit bad_found = 0;

    for (int t = 0; t < 30; t++) begin
      automatic int ok;

      m  = new();
      ok = m.randomize();

      if (!ok) begin
        $display("FAIL: randomize() returned 0 at call %0d", t);
        $fatal(1);
      end

      if (m.regions.size() < 4 || m.regions.size() > 8) begin
        $display("FAIL: regions.size()=%0d is outside [4:8] at call %0d", m.regions.size(), t);
        bad_found = 1;
      end

      foreach (m.regions[i]) begin
        if (m.regions[i].base_addr >= m.regions[i].limit_addr) begin
          $display("FAIL: regions[%0d] base_addr=%08h is not < limit_addr=%08h at call %0d", i,
                   m.regions[i].base_addr, m.regions[i].limit_addr, t);
          bad_found = 1;
        end
        if (m.regions[i].base_addr > 32'h7FFF_FFFF || m.regions[i].limit_addr > 32'h7FFF_FFFF) begin
          $display("FAIL: regions[%0d] [%08h:%08h] exceeds the 32'h7FFF_FFFF bound at call %0d", i,
                   m.regions[i].base_addr, m.regions[i].limit_addr, t);
          bad_found = 1;
        end
        if ((m.regions[i].limit_addr - m.regions[i].base_addr + 1) % 32'h1000 != 0) begin
          $display("FAIL: regions[%0d] size=%0d is not a multiple of 4096 at call %0d", i,
                   m.regions[i].limit_addr - m.regions[i].base_addr + 1, t);
          bad_found = 1;
        end
        if (m.regions[i].base_addr % 32'h1000 != 0) begin
          $display("FAIL: regions[%0d].base_addr=%08h is not 4K-aligned at call %0d", i,
                   m.regions[i].base_addr, t);
          bad_found = 1;
        end
        if (i > 0 && m.regions[i].base_addr <= m.regions[i-1].base_addr) begin
          $display("FAIL: regions[%0d].base_addr=%08h does not exceed regions[%0d].base_addr=%08h "
                   , i, m.regions[i].base_addr, i - 1, m.regions[i-1].base_addr);
          bad_found = 1;
        end
      end

      // full pairwise overlap check, not just adjacent -- independently verifies requirement 7
      // regardless of whether the learner's fix actually keeps the array sorted
      for (int i = 0; i < m.regions.size(); i++) begin
        for (int j = i + 1; j < m.regions.size(); j++) begin
          if (m.regions[i].base_addr <= m.regions[j].limit_addr
              && m.regions[j].base_addr <= m.regions[i].limit_addr) begin
            $display("FAIL: regions[%0d] [%08h:%08h] overlaps regions[%0d] [%08h:%08h] at call %0d",
                     i, m.regions[i].base_addr, m.regions[i].limit_addr, j, m.regions[j].base_addr,
                     m.regions[j].limit_addr, t);
            bad_found = 1;
          end
        end
      end

      if (bad_found) $fatal(1);
    end

    $display("PASS: 30 calls, every memory map sized/ordered/aligned/non-overlapping");
    $finish;
  end
endmodule
