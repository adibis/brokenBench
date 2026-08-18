// =================================================================================================
// three techniques, one class, all of them have to actually work together
// =================================================================================================
//
// REQUIRES A PATCHED VERILATOR -- see the note in README.md before you spend time on this one.
// `unique{}` on a foreach-indexed row of a 2D array crashes the compiler outright on every
// released Verilator as of this writing (an internal fault, not a graceful error) -- the same bug
// `thermal_power_fuzzer` avoids entirely by using pairwise inequality instead. This exercise is
// that same construct, at real scale, combined with everything else below:
//
//   make run EX=dma_ring_allocator VERILATOR=/path/to/patched/verilator_bin
//
// A DMA scheduler's allocation grid: 4 channels, each with 4 ring-buffer slots, each slot holding
// an 8-bit physical-block pointer. Nothing here is individually exotic -- row/column uniqueness,
// a weighted mode pick, a conditional bound, a conditional sum -- but getting all three to hold at
// once, in the same randomize() call, is where it actually gets hard.
//
//   - every channel (row) must route to entirely distinct blocks, AND every slot-index across
//     channels (column) must too. A row has a natural answer -- `grid[i]` is already a valid
//     array-typed slice, so `unique {grid[i]}` names the whole row in one shot. A column doesn't:
//     there's no `grid[:][j]` slicing syntax in SystemVerilog, so unique{}'s range_list has to be
//     given the column's elements explicitly, one by one, inside something that iterates the
//     column index. IEEE 1800-2023 18.5.4 is the section to read if you want to know why a whole
//     row and a single cell inside a foreach over that row aren't equivalent.
//   - qos_mode has to land on BURST_MODE 70% of the time and SPARSE_MODE 30%, and which
//     bound/sum requirement applies depends on which mode was picked -- `solve ... before` has to
//     sequence qos_mode ahead of dma_grid, or nothing downstream is guaranteed to see a settled
//     value to condition on.
//   - the BURST_MODE sum is over channel 1's whole row UNION slot 3's whole column -- not the sum
//     of both taken separately. Row 1 and column 3 share exactly one cell (dma_grid[1][3]); count
//     it once. Summing all 4 row cells plus all 4 column cells adds that shared cell twice, which
//     quietly makes the >1000 requirement easier to satisfy than it's supposed to be -- exactly
//     the kind of bug that still passes a handful of manual spot checks.
//
// Fix the class below so the check after it passes.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Write the class so, on every randomize() call:
//
//   1. every dma_grid[ch][slot] is inside [1:255].
//   2. within any one channel (row), all 4 slot values are distinct. Within any one slot-index
//      (column), all 4 channel values are distinct. Use unique{} for both, not pairwise
//      inequality.
//   3. qos_mode resolves to BURST_MODE 70% of the time, SPARSE_MODE 30% of the time.
//   4. if qos_mode == SPARSE_MODE, every cell in the grid is inside [1:20].
//   5. if qos_mode == BURST_MODE, the sum of the 7 distinct cells in channel 1's row union slot
//      3's column (not 8 -- the shared cell counts once) is strictly greater than 1000.
// -------------------------------------------------------------------------------------------------
class DmaRingAllocator;
  rand bit [7:0] dma_grid[4][4];

  typedef enum bit {SPARSE_MODE, BURST_MODE} qos_mode_e;
  rand qos_mode_e qos_mode;

  constraint c_base_bounds {
    foreach (dma_grid[ch, slot]) {
      dma_grid[ch][slot] inside {[1 : 255]};
    }
  }

  // write the rest of the constraints here
endclass

// ---8<--- checker below: don't edit ---

module top;
  initial begin
    DmaRingAllocator d;
    int ok;
    int total = 300;
    int burst_cnt = 0, sparse_cnt = 0;
    bit bad_found = 0;

    for (int t = 0; t < total; t++) begin
      d = new();
      ok = d.randomize();
      if (!ok) begin
        $display("FAIL: randomize() returned 0 at trial %0d", t);
        $fatal(1);
      end

      for (int ch = 0; ch < 4; ch++)
      for (int slot = 0; slot < 4; slot++)
      if (d.dma_grid[ch][slot] < 1 || d.dma_grid[ch][slot] > 255) begin
        $display("FAIL: dma_grid[%0d][%0d]=%0d outside [1:255] at trial %0d", ch, slot,
                 d.dma_grid[ch][slot], t);
        bad_found = 1;
      end

      for (int ch = 0; ch < 4; ch++)
      for (int x = 0; x < 4; x++)
      for (int y = x + 1; y < 4; y++)
      if (d.dma_grid[ch][x] == d.dma_grid[ch][y]) begin
        $display("FAIL: channel %0d has a repeated pointer at trial %0d: %p", ch, t,
                 d.dma_grid[ch]);
        bad_found = 1;
      end

      for (int slot = 0; slot < 4; slot++)
      for (int x = 0; x < 4; x++)
      for (int y = x + 1; y < 4; y++)
      if (d.dma_grid[x][slot] == d.dma_grid[y][slot]) begin
        $display("FAIL: slot %0d has a repeated pointer across channels at trial %0d", slot, t);
        bad_found = 1;
      end

      if (d.qos_mode == d.BURST_MODE) burst_cnt++;
      else sparse_cnt++;

      if (d.qos_mode == d.SPARSE_MODE) begin
        for (int ch = 0; ch < 4; ch++)
        for (int slot = 0; slot < 4; slot++)
        if (d.dma_grid[ch][slot] < 1 || d.dma_grid[ch][slot] > 20) begin
          $display("FAIL: SPARSE_MODE dma_grid[%0d][%0d]=%0d outside [1:20] at trial %0d", ch,
                   slot, d.dma_grid[ch][slot], t);
          bad_found = 1;
        end
      end else begin
        automatic int union_sum;
        union_sum = d.dma_grid[1][0] + d.dma_grid[1][1] + d.dma_grid[1][2] + d.dma_grid[1][3]
                  + d.dma_grid[0][3] + d.dma_grid[2][3] + d.dma_grid[3][3];
        if (union_sum <= 1000) begin
          $display("FAIL: BURST_MODE row1-union-col3 sum=%0d, expected > 1000 at trial %0d",
                   union_sum, t);
          bad_found = 1;
        end
      end
    end

    if (bad_found) $fatal(1);

    if (burst_cnt < (total * 65 / 100) || burst_cnt > (total * 75 / 100)) begin
      $display("FAIL: BURST_MODE %0d/%0d (%0d%%), expected roughly 70%%", burst_cnt, total,
               (burst_cnt * 100) / total);
      $fatal(1);
    end

    $display("PASS: %0d trials -- BURST_MODE=%0d%% SPARSE_MODE=%0d%%, all row/col uniqueness, ",
             total, (burst_cnt * 100) / total, (sparse_cnt * 100) / total);
    $display("      mode bounds, and cross-sum requirements held");
    $finish;
  end
endmodule
