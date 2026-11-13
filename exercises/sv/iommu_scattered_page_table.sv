// =================================================================================================
// no sorting allowed: check every pair, not just neighbors
// =================================================================================================
//
// nonoverlapping_address_ranges could check each region only against its predecessor because
// the array was sorted. Physical pages here are scattered in no order, so page 3 can overlap page
// 9 as easily as page 4. Every pair needs checking: a nested foreach over the same array, inside
// the constraint.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements:
//
//   1. page_table.size() is between 8 and 16, inclusive.
//   2. v_start_addr[0] is 32'h1000_0000, and each later v_start_addr[i] is v_start_addr[i-1] +
//      page_size[i-1]: virtual space is contiguous, with no gaps or overlaps.
//   3. Every page_size is 4KB (32'h1000), 64KB (32'h10000) or 2MB (32'h200000).
//   4. Nothing orders p_start_addr by index: physical pages may land anywhere, in any order.
//   5. No two physical pages overlap, checked for every pair i != j.
//   6. No two physical pages are adjacent: p_start_addr[i] never equals p_start_addr[j] +
//      page_size[j], for every pair i != j.
//   7. Every physical page fits inside [32'h0000_0000 : 32'hFFFF_FFFF]. A plain
//      `p_start_addr + page_size <= 32'hFFFF_FFFF` wraps at 32 bits near the top and lets an
//      out-of-range page through.
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
