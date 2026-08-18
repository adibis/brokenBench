// =================================================================================================
// sorted isn't the same as non-overlapping -- unless you check the right pair
// =================================================================================================
//
// A classic memory-allocator constraint: hand out N address ranges that don't overlap. Ordering
// just the *starts* (`regions[0].base < regions[1].base < ...`) looks like it accomplishes that --
// nothing about the constraint is obviously wrong -- but it says nothing about where each range
// actually *ends*. A large enough region reaches straight into the next one, sorted starting
// addresses and all.
//
// The fix isn't to compare every region against every other region -- once the array is genuinely
// kept in ascending order by base_addr, checking each region only against its immediate
// predecessor is enough: if region i doesn't reach into region i+1, and region i+1 doesn't reach
// into region i+2, nothing earlier can reach past i+1 either, because everything is already
// sorted. That's the whole reason to maintain the ordering in the first place -- it turns an
// all-pairs check into an adjacent-pairs check.
//
// One more thing worth being deliberate about: `regions[i-1]` only makes sense once `i > 0`.
// `i` in a foreach loop is unsigned, so guard that access with a real if/else, not a bare `if`
// with nothing to fall through to at i==0 -- a stray reference to index -1 on an unsigned type
// wraps to the largest possible value instead of going negative, the same silent-wraparound
// trap iommu_scattered_page_table's physical-bounds check calls out for address arithmetic.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so:
//
//   1. regions.size() is randomized to somewhere between 4 and 8, inclusive.
//   2. regions[] stays in strictly ascending order by base_addr.
//   3. every region's base_addr is strictly less than its own limit_addr.
//   4. every base_addr and limit_addr stays within [32'h0000_0000 : 32'h7FFF_FFFF].
//   5. every region's size (limit_addr - base_addr + 1 -- limit_addr is the region's last byte,
//      inclusive) is an exact multiple of 4KB (32'h1000).
//   6. every region's base_addr is itself 4KB-aligned (a multiple of 32'h1000), not just its size.
//   7. no two regions overlap -- given requirement 2 already holds, this only needs checking each
//      region's base_addr against the *previous* region's limit_addr.
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
