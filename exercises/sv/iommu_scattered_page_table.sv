// =================================================================================================
// no sorting allowed: check every pair, not just neighbors
// =================================================================================================
//
// The trick that makes nonoverlapping_address_ranges cheap -- keep the array sorted, then only
// check each element against its immediate predecessor -- depends entirely on the array actually
// being sorted. Take that away and the shortcut goes with it: with physical pages genuinely
// scattered in no particular order, page 3 could overlap page 9 just as easily as page 4, and
// there's no single neighbor whose check would have caught it. The only way to be sure none of
// them touch is to check every pair, not just adjacent ones -- an ordinary nested `foreach`
// (a loop inside a loop, both walking the same array) inside a `constraint` block, comparing
// each pair once.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the constraints so:
//
//   1. page_table.size() is randomized to somewhere between 8 and 16, inclusive.
//   2. v_start_addr[0] is exactly 32'h1000_0000. For every later entry, v_start_addr[i] equals
//      v_start_addr[i-1] + page_size[i-1] -- the virtual space is one unbroken continuum, no
//      gaps and no overlaps, entry by entry.
//   3. Every page_size is one of exactly three values: 4KB (32'h1000), 64KB (32'h10000), or
//      2MB (32'h200000).
//   4. Do NOT add any constraint that orders p_start_addr by index -- physical pages must be free
//      to land anywhere, in any order.
//   5. No two physical pages overlap. Since nothing keeps the array sorted, this means checking
//      every pair (i, j) with i != j, not just neighbors.
//   6. No two physical pages are adjacent either -- page i's p_start_addr must never land exactly
//      where page j ends (p_start_addr[j] + page_size[j]), for every pair i != j.
//   7. Every physical page fits inside [32'h0000_0000 : 32'hFFFF_FFFF]. Watch the upper bound: a
//      naive `p_start_addr + page_size <= 32'hFFFF_FFFF` can silently wrap around 32 bits near the
//      top of the range and let an out-of-bounds page through looking valid.
// -------------------------------------------------------------------------------------------------
typedef struct {
  rand bit [31:0] v_start_addr;
  rand bit [31:0] p_start_addr;
  rand bit [31:0] page_size;
} map_entry_s;

class IommuTranslationTable;
  rand map_entry_s page_table[];

  // write constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    IommuTranslationTable t;
    bit bad_found = 0;

    for (int trial = 0; trial < 8; trial++) begin
      automatic int ok;

      t  = new();
      ok = t.randomize();

      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", trial);
        $fatal(1);
      end

      if (t.page_table.size() < 8 || t.page_table.size() > 16) begin
        $display("FAIL: page_table.size()=%0d is outside [8:16] at trial %0d", t.page_table.size(),
                 trial);
        bad_found = 1;
      end

      foreach (t.page_table[i]) begin
        if (i == 0 && t.page_table[i].v_start_addr != 32'h1000_0000) begin
          $display("FAIL: page_table[0].v_start_addr=%08h, expected 32'h1000_0000 at trial %0d",
                   t.page_table[i].v_start_addr, trial);
          bad_found = 1;
        end
        if (i > 0 && t.page_table[i].v_start_addr
                     != t.page_table[i-1].v_start_addr + t.page_table[i-1].page_size) begin
          $display("FAIL: v_start_addr[%0d]=%08h breaks the virtual continuum at trial %0d", i,
                   t.page_table[i].v_start_addr, trial);
          bad_found = 1;
        end
        if (!(t.page_table[i].page_size inside {32'h1000, 32'h10000, 32'h200000})) begin
          $display("FAIL: page_table[%0d].page_size=%0d is not 4KB/64KB/2MB at trial %0d", i,
                   t.page_table[i].page_size, trial);
          bad_found = 1;
        end
        if (t.page_table[i].p_start_addr > 32'hFFFF_FFFF - t.page_table[i].page_size + 1) begin
          $display("FAIL: page_table[%0d] p_start_addr=%08h size=%0d exceeds the physical bound "
                   , i, t.page_table[i].p_start_addr, t.page_table[i].page_size);
          bad_found = 1;
        end
      end

      for (int i = 0; i < t.page_table.size(); i++) begin
        for (int j = i + 1; j < t.page_table.size(); j++) begin
          if (t.page_table[i].p_start_addr
              < t.page_table[j].p_start_addr + t.page_table[j].page_size
              && t.page_table[j].p_start_addr
                 < t.page_table[i].p_start_addr + t.page_table[i].page_size) begin
            $display("FAIL: page_table[%0d] overlaps page_table[%0d] at trial %0d", i, j, trial);
            bad_found = 1;
          end
          if (t.page_table[i].p_start_addr
              == t.page_table[j].p_start_addr + t.page_table[j].page_size
              || t.page_table[j].p_start_addr
                 == t.page_table[i].p_start_addr + t.page_table[i].page_size) begin
            $display("FAIL: page_table[%0d] is adjacent to page_table[%0d] at trial %0d", i, j,
                     trial);
            bad_found = 1;
          end
        end
      end

      if (bad_found) $fatal(1);
    end

    $display("PASS: 8 trials, every page table virtually continuous and physically scattered");
    $finish;
  end
endmodule
