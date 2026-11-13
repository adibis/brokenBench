// =================================================================================================
// three techniques, one class, all of them have to actually work together
// =================================================================================================
//
// REQUIRES A PATCHED VERILATOR: see README.md first. `unique{}` on a foreach-indexed row of a 2D
// array crashes the compiler on every released Verilator as of this writing, the same bug
// thermal_power_fuzzer avoids with pairwise inequality. This exercise uses it at full scale:
//
//   make run EX=dma_ring_allocator VERILATOR=/path/to/patched/verilator_bin
//
// A DMA scheduler's allocation grid: 4 channels of 4 ring-buffer slots, each holding an 8-bit
// block pointer. Each requirement is ordinary; making them all hold in one randomize() is the
// hard part.
//
//   - Rows and columns must both be distinct. `grid[i]` is already an array, so
//     `unique {grid[i]}` covers a row. There's no `grid[:][j]` column slice, so a column's
//     elements have to be listed explicitly inside something that iterates the column index.
//     IEEE 1800-2023 18.5.4 explains why a whole row and one cell inside a foreach over it differ.
//   - Which bound applies depends on qos_mode, so `solve ... before` has to settle qos_mode
//     ahead of dma_grid.
//   - The BURST_MODE sum is over row 1 union column 3. They share dma_grid[1][3]; count it once.
//     Counting it twice makes the >1000 bound easier to meet than intended.
//
// Fix the class below.
// Don't edit anything at or below the "checker" marker.

// -------------------------------------------------------------------------------------------------
// Requirements, on every randomize() call:
//
//   1. Every dma_grid[ch][slot] is in [1:255].
//   2. Each row's 4 values are distinct, and each column's 4 values are distinct, using
//      unique{} for both, not pairwise inequality.
//   3. qos_mode is BURST_MODE 70% of the time, SPARSE_MODE 30%.
//   4. In SPARSE_MODE, every cell is in [1:20].
//   5. In BURST_MODE, the 7 distinct cells of row 1 union column 3 sum to more than 1000.
// -------------------------------------------------------------------------------------------------
class DmaRingAllocator;
  rand bit [7:0] dma_grid[4][4];

  typedef enum bit {
    SPARSE_MODE,
    BURST_MODE
  } qos_mode_e;
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
      d  = new();
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
